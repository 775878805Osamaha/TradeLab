package com.example.core.market

import android.content.Context
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.example.core.model.Candle
import com.example.core.model.Tick
import com.example.core.model.Timeframe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Only the cTrader read-only gateway is permitted for metals and forex. */
class CTraderGatewayClient(context: Context, private val origin: String = GATEWAY_ORIGIN) {
    data class Account(val id: String, val isLive: Boolean, val broker: String)
    private val secureStore = SessionStore(context)
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS).readTimeout(25, TimeUnit.SECONDS)
        .followRedirects(false).build()
    private val lock = Any()
    private var session = secureStore.read().optString("session")
    private var selectedId = secureStore.read().optString("account")
    private var pendingVerifier: String? = null
    @Volatile private var quoteNotBefore = System.currentTimeMillis()
    private val _accountGeneration = MutableStateFlow(0L)
    val accountGeneration: StateFlow<Long> = _accountGeneration
    private val symbolIds = HashMap<String, Long>()
    private val symbolPrecisionCache = HashMap<String, RangeSymbolPrecision>()
    private val missingSymbolDetailUntil = HashMap<String, Long>()

    private val _status = MutableStateFlow(if (session.isBlank()) "غير مرتبط بـ cTrader" else "جارٍ التحقق من cTrader")
    val status: StateFlow<String> = _status
    private val _accounts = MutableStateFlow<List<Account>>(emptyList())
    val accounts: StateFlow<List<Account>> = _accounts
    private val _selectedAccount = MutableStateFlow(selectedId)
    val selectedAccount: StateFlow<String> = _selectedAccount

    fun isLinked(): Boolean = synchronized(lock) { session.isNotBlank() }

    fun reportError(reason: String) { _status.value = "تعذر ربط cTrader: ${reason.take(200)}" }

    /** The challenge is SHA-256(verifier); the verifier never enters the browser URL. */
    fun beginAuthorization(): String {
        val bytes = ByteArray(32).also(SecureRandom()::nextBytes)
        val verifier = Base64.encodeToString(bytes, Base64.NO_PADDING or Base64.NO_WRAP or Base64.URL_SAFE)
        synchronized(lock) { pendingVerifier = verifier }
        // An old account badge is not evidence of a successful new login.
        _accounts.value = emptyList()
        _selectedAccount.value = ""
        val challenge = Base64.encodeToString(MessageDigest.getInstance("SHA-256")
            .digest(verifier.toByteArray(Charsets.UTF_8)), Base64.NO_PADDING or Base64.NO_WRAP or Base64.URL_SAFE)
        _status.value = "أكمل تفويض القراءة فقط عبر المتصفح"
        return "$origin/auth/ctrader/start?challenge=$challenge"
    }

    fun isCallback(uri: Uri): Boolean {
        val ticket = uri.getQueryParameter("ticket")
        return uri.scheme == "tradelab" && uri.host == "oauth" &&
            uri.path == "/ctrader" && ticket != null && ticket.length in 1..6144
    }

    suspend fun completeAuthorization(uri: Uri) {
        require(isCallback(uri)) { "Invalid cTrader callback" }
        val verifier = synchronized(lock) { pendingVerifier.also { pendingVerifier = null } }
            ?: throw IOException("انتهت جلسة التفويض؛ ابدأ ربط cTrader مرة أخرى")
        val ticket = uri.getQueryParameter("ticket") ?: throw IOException("Missing handoff ticket")
        val response = request("/auth/ctrader/redeem", JSONObject()
            .put("ticket", ticket).put("verifier", verifier))
        require(response.optString("permission") == "read_only") { "cTrader did not grant read-only access" }
        val token = response.optString("sessionToken")
        require(token.isNotBlank() && token.length <= 6144) { "Invalid cTrader session" }
        synchronized(lock) {
            session = token; selectedId = ""; symbolIds.clear()
            symbolPrecisionCache.clear(); missingSymbolDetailUntil.clear()
            quoteNotBefore = System.currentTimeMillis()
            persist()
        }
        _accounts.value = emptyList()
        _selectedAccount.value = ""
        _accountGeneration.value += 1L
        refreshAccounts()
    }

    suspend fun refreshAccounts() {
        if (!isLinked()) { _status.value = "اربط حساب cTrader أولاً"; return }
        try {
            val json = request("/v1/accounts")
            val array = json.getJSONArray("accounts")
            val list = (0 until array.length()).mapNotNull { index ->
                val account = array.getJSONObject(index)
                val id = account.optString("accountId")
                if (!id.matches(Regex("[1-9][0-9]*"))) null else Account(
                    id, account.optBoolean("isLive"), account.optString("broker"))
            }
            if (list.isEmpty()) throw IOException("لم يظهر حساب cTrader مخوّل للقراءة")
            val next = synchronized(lock) { selectedId }.takeIf { id -> list.any { it.id == id } } ?: list.first().id
            // Fetch symbol permissions before claiming the account is ready.
            val ids = fetchSymbols(next)
            commitSelection(next, ids, list)
        } catch (error: Exception) {
            synchronized(lock) { selectedId = ""; symbolIds.clear()
                symbolPrecisionCache.clear(); missingSymbolDetailUntil.clear(); persist() }
            _accounts.value = emptyList()
            _selectedAccount.value = ""
            _accountGeneration.value += 1L
            _status.value = "تعذر الاتصال بـ cTrader: ${error.message?.take(180)}"
            throw error
        }
    }

    suspend fun selectAccount(accountId: String) {
        require(accounts.value.any { it.id == accountId }) { "Unauthorized cTrader account" }
        val ids = fetchSymbols(accountId)
        commitSelection(accountId, ids, accounts.value)
    }

    private suspend fun fetchSymbols(accountId: String): HashMap<String, Long> {
        val json = request("/v1/symbols?accountId=$accountId")
        val array = json.getJSONArray("symbols")
        val ids = HashMap<String, Long>()
        for (i in 0 until array.length()) {
            val symbol = array.getJSONObject(i)
            val name = symbol.optString("symbolName").ifBlank { symbol.optString("name") }
                .uppercase().replace("/", "")
            val id = symbol.optLong("symbolId", 0)
            if (name in VerifiedMarketQuote.forexSymbols && id > 0L && !symbol.optBoolean("archived", false))
                ids[name] = id
        }
        return ids
    }

    private fun commitSelection(accountId: String, ids: Map<String, Long>, allowed: List<Account>) {
        synchronized(lock) {
            selectedId = accountId
            symbolIds.clear()
            symbolIds.putAll(ids)
            symbolPrecisionCache.clear()
            missingSymbolDetailUntil.clear()
            quoteNotBefore = System.currentTimeMillis()
            persist()
        }
        _accounts.value = allowed
        _accountGeneration.value += 1L
        _selectedAccount.value = accountId
        _status.value = if (ids.isEmpty()) "مرتبط، لكن الوسيط لا يعرض رموز الفوركس المطلوبة" else
            "متصل بـ cTrader للقراءة فقط (${ids.size} رموز)"
    }

    fun logout() {
        synchronized(lock) {
            session = ""; selectedId = ""; pendingVerifier = null
            quoteNotBefore = System.currentTimeMillis()
            symbolIds.clear(); symbolPrecisionCache.clear(); missingSymbolDetailUntil.clear(); persist()
        }
        _accountGeneration.value += 1L
        _accounts.value = emptyList(); _selectedAccount.value = ""
        _status.value = "غير مرتبط بـ cTrader"
    }

    fun sourceKey(symbol: String): String {
        val (account, id) = resolve(symbol)
        return sourceName(account, id)
    }

    /** Read the broker's full symbol (not the light symbols list). An older,
     * undeployed gateway returns null; never manufacture broker metadata. */
    suspend fun symbolPrecision(symbol: String): RangeSymbolPrecision? {
        val (account, id) = resolve(symbol)
        val key = sourceName(account, id)
        synchronized(lock) { symbolPrecisionCache[key] }?.let { return it }
        if (synchronized(lock) { (missingSymbolDetailUntil[key] ?: 0L) > System.currentTimeMillis() })
            return null
        val json = try {
            request("/v1/symbol-detail?accountId=$account&symbolId=$id")
        } catch (missing: CTraderGatewayException) {
            if (missing.statusCode == 404) {
                synchronized(lock) {
                    if (sourceName(account, id) == key)
                        missingSymbolDetailUntil[key] = System.currentTimeMillis() + 60_000L
                }
                return null
            }
            throw missing
        }
        if (resolve(symbol) != (account to id) || sourceName(account, id) != key)
            throw IOException("cTrader account changed during symbol metadata request")
        require(json.optString("source") == "ctrader" &&
            json.optString("symbolId") == id.toString() &&
            json.optString("accountId") == account &&
            json.has("digits") && json.has("pipPosition")) {
            "Incorrect cTrader symbol metadata source"
        }
        val metadata = RangeSymbolPrecision(json.getInt("digits"), json.getInt("pipPosition"))
        synchronized(lock) { if (sourceName(account, id) == key) symbolPrecisionCache[key] = metadata }
        return metadata
    }

    /** Reject quotes from a prior broker account even during their 15-second freshness window. */
    fun isCurrentQuote(tick: Tick): Boolean = synchronized(lock) {
        session.isNotBlank() && selectedId.isNotBlank() &&
            symbolIds.containsKey(tick.symbol) && tick.timestamp >= quoteNotBefore
    }

    private fun sourceName(account: String, id: Long): String {
        val environment = if (accounts.value.firstOrNull { it.id == account }?.isLive == true) "live" else "demo"
        return "ctrader:$environment:$account:$id"
    }

    suspend fun spot(symbol: String): Tick {
        val (account, id) = resolve(symbol)
        val json = request("/v1/spot?accountId=$account&symbolId=$id")
        if (resolve(symbol) != (account to id)) throw IOException("cTrader account changed during quote request")
        require(json.optString("source") == "ctrader" && json.optString("symbolId") == id.toString()) {
            "Wrong cTrader quote source"
        }
        val tick = Tick(symbol, json.getDouble("bid"), json.getDouble("ask"),
            timestamp = json.getLong("timestamp"), source = "CTRADER_GATEWAY")
        require(VerifiedMarketQuote.isVerified(tick, symbol)) { "cTrader quote is stale or invalid" }
        return tick
    }

    /**
     * Real historical BID quotes for fixed Range Bars. Never reconstruct
     * ticks from the OHLC trendbars endpoint. Each broker page may be truncated.
     */
    suspend fun historicalBidTicks(symbol: String, from: Long, to: Long): List<RangePriceTick> =
        withContext(Dispatchers.IO) {
            val (account, id) = resolve(symbol)
            val source = sourceName(account, id)
            require(from > 0 && to >= from && to <= System.currentTimeMillis() &&
                to - from <= 604_800_000L) { "نطاق Tick لا يتجاوز أسبوعًا واحدًا" }
            val json = try {
                request("/v1/ticks?accountId=$account&symbolId=$id&from=$from&to=$to")
            } catch (error: CTraderGatewayException) {
                if (error.statusCode == 404)
                    throw IOException("بوابة cTrader لم تُحدَّث بعد لدعم تاريخ Tick؛ يلزم نشر /v1/ticks", error)
                throw error
            }
            if (resolve(symbol) != (account to id) || sourceName(account, id) != source)
                throw IOException("cTrader account changed during tick history request")
            require(json.optString("source") == "ctrader" &&
                json.optString("quoteType") == "bid" &&
                json.optString("symbolId") == id.toString()) { "Wrong broker tick source" }
            // hasMore means the broker did NOT return all quotes within the
            // interval. Never page by oldestTimestamp-1: multiple genuine BID
            // changes can share that millisecond. The batch loader splits
            // the time interval into contiguous halves and retries safely.
            if (json.optBoolean("hasMore")) throw RangeTickHistoryTooDenseException(
                "cTrader أعاد بيانات Tick غير مكتملة؛ جارٍ تقسيم الفترة للحصول على الأسعار كلها")
            val values = json.getJSONArray("ticks")
            require(values.length() <= 100_000) { "Oversized broker tick page" }
            val quotes = ArrayList<RangePriceTick>(values.length())
            var previous = -1L
            for (i in 0 until values.length()) {
                val raw = values.getJSONObject(i)
                val timestamp = raw.getLong("timestamp")
                val price = raw.getDouble("price")
                require(timestamp in from..to && timestamp >= previous &&
                    price.isFinite() && price > 0.0) { "Invalid broker tick history" }
                quotes.add(RangePriceTick(timestamp, price))
                previous = timestamp
            }
            quotes
        }

    suspend fun candles(symbol: String, timeframe: Timeframe, from: Long, to: Long): List<Candle> {
        val (account, id) = resolve(symbol)
        val period = if (timeframe == Timeframe.H2) Timeframe.H1 else timeframe
        require(CTraderTrendbars.period(period) != null) { "Unsupported cTrader timeframe" }
        require(from >= 0L && to >= from && to <= System.currentTimeMillis()) { "Invalid closed candle range" }
        val interval = period.minutes * 60_000L
        val sourceTo = if (timeframe == Timeframe.H2) to + 3_600_000L else to
        val source = sourceName(account, id)
        val verified = CTraderHistoryPaging.load(from, sourceTo, interval, timeOf = { it.openTime }) { start, end, count ->
            val url = "/v1/candles?accountId=$account&symbolId=$id&period=${period.code}" +
                "&from=$start&to=${end + 1}&count=$count"
            val json = request(url)
            if (resolve(symbol) != (account to id) || sourceName(account, id) != source) {
                throw IOException("cTrader account changed during history request")
            }
            require(json.optString("source") == "ctrader" && json.optString("symbolId") == id.toString() &&
                json.optString("period") == period.code) { "Wrong cTrader history source" }
            val array = json.getJSONArray("candles")
            val candles = buildList {
                for (i in 0 until array.length()) {
                    val bar = array.getJSONObject(i)
                    val openTime = bar.getLong("timestamp")
                    if (openTime !in start..end || openTime + interval > System.currentTimeMillis()) continue
                    val candle = Candle(symbol, period, openTime, openTime + interval,
                        bar.getDouble("open"), bar.getDouble("high"), bar.getDouble("low"),
                        bar.getDouble("close"), bar.getDouble("volume"), source)
                    require(DataIntegrityValidator.validateCandle(candle).isValid) { "Corrupt cTrader candle" }
                    add(candle)
                }
            }
            // A truncated response still contains real bars. Preserve them and
            // fetch older pages using the earliest returned timestamp.
            CTraderHistoryPaging.Page(candles, hasMore = json.optBoolean("hasMore"))
        }.let { candles ->
            HistoricalCandleIntegrity.validate(CTraderTrendbars.closeAtNextBrokerOpen(candles), from, sourceTo + interval,
                expectedSource = source, expectedSymbol = symbol, expectedTimeframe = period)
        }
        if (timeframe != Timeframe.H2) return verified
        // H2 is not a native cTrader period. Derive it only from real, fully
        // closed H1 pairs, allowing the broker's minute-level open-tick shifts.
        val paired = CTraderTrendbars.aggregateVerifiedH2(verified)
            .filter { it.openTime in from..to }
        return HistoricalCandleIntegrity.validate(paired, from, to + 7_200_000L,
            expectedSource = source, expectedSymbol = symbol, expectedTimeframe = Timeframe.H2)
    }

    private fun resolve(symbol: String): Pair<String, Long> = synchronized(lock) {
        require(symbol in VerifiedMarketQuote.forexSymbols) { "Not a cTrader forex/metal symbol" }
        if (session.isBlank() || selectedId.isBlank()) throw IOException("اربط حساب cTrader في الإعدادات")
        val id = symbolIds[symbol] ?: throw IOException("الرمز $symbol غير متاح لدى وسيط cTrader")
        selectedId to id
    }

    private data class HttpPayload(val status: Int, val content: String, val refreshedSession: String?)

    /** Cancel a pending HTTP request as soon as the chart's window changes.
     * Blocking execute() previously occupied the Range mutex until the
     * network timeout even after the user switched symbols or Range sizes. */
    private suspend fun awaitHttp(request: Request, maxChars: Int, tickPage: Boolean): HttpPayload =
        suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    if (!continuation.isActive) {
                        response.close()
                        return
                    }
                    try {
                        response.use { received ->
                            if (received.isSuccessful && received.body?.contentLength()?.let { it > maxChars } == true)
                                throw if (tickPage) RangeTickHistoryTooDenseException(
                                    "صفحة Tick كبيرة؛ يلزم تقسيم الفترة")
                                else IOException("Oversized cTrader response")
                            val content = received.body?.string()
                                ?: throw IOException("Empty cTrader response")
                            if (received.isSuccessful && content.length > maxChars)
                                throw if (tickPage) RangeTickHistoryTooDenseException(
                                    "صفحة Tick كبيرة؛ يلزم تقسيم الفترة")
                                else IOException("Oversized cTrader response")
                            if (continuation.isActive) continuation.resume(HttpPayload(
                                received.code, content, received.header("X-TradeLab-Session")))
                        }
                    } catch (error: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(error)
                    }
                }
            })
        }

    private suspend fun request(path: String, post: JSONObject? = null): JSONObject = withContext(Dispatchers.IO) {
        require(origin.startsWith("https://") && !origin.contains('@')) { "HTTPS gateway required" }
        val token = synchronized(lock) { session }
        val builder = Request.Builder().url(origin + path).header("Accept", "application/json")
        if (path.startsWith("/v1/")) {
            if (token.isBlank()) throw IOException("cTrader login required")
            builder.header("Authorization", "Bearer $token")
        }
        if (post != null) builder.post(post.toString().toRequestBody("application/json".toMediaType()))
        val tickPage = path.startsWith("/v1/ticks")
        val wire = awaitHttp(builder.build(), if (tickPage) 8_000_000 else 2_000_000, tickPage)
        if (wire.status !in 200..299) {
            val body = wire.content.take(2048)
            val code = runCatching { JSONObject(body).optString("error") }.getOrNull()
            throw CTraderGatewayException(wire.status, code)
        }
        val json = JSONObject(wire.content)
        wire.refreshedSession?.let { newToken ->
            if (newToken.isNotBlank() && newToken.length <= 6144) synchronized(lock) {
                // A slow request cannot overwrite the session after logout/account change.
                if (session == token) { session = newToken; persist() }
            }
        }
        json
    }

    private fun persist() { secureStore.save(JSONObject().put("session", session).put("account", selectedId)) }

    private class SessionStore(context: Context) {
        private val file = File(context.noBackupFilesDir, "ctrader-session-v1")
        private val alias = "tradelab.ctrader.session.v1"
        private fun key(): SecretKey {
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (store.getKey(alias, null) as? SecretKey)?.let { return it }
            return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            }.generateKey()
        }
        @Synchronized fun read(): JSONObject = try {
            if (!file.exists()) JSONObject() else {
                val bytes = file.readBytes()
                require(bytes.size > 28)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
            }
        } catch (_: Exception) { JSONObject() }
        @Synchronized fun save(value: JSONObject) {
            if (value.optString("session").isBlank()) { if (file.exists()) check(file.delete()); return }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val temp = File(file.parentFile, file.name + ".tmp")
            temp.writeBytes(cipher.iv + cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8)))
            check(temp.renameTo(file))
        }
    }

    companion object { const val GATEWAY_ORIGIN = "https://tradelab-vercel-gateway.vercel.app" }
}
