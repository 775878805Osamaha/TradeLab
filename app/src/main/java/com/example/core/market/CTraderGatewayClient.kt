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
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
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
            synchronized(lock) { selectedId = ""; symbolIds.clear(); persist() }
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
            symbolIds.clear(); persist()
        }
        _accountGeneration.value += 1L
        _accounts.value = emptyList(); _selectedAccount.value = ""
        _status.value = "غير مرتبط بـ cTrader"
    }

    fun sourceKey(symbol: String): String {
        val (account, id) = resolve(symbol)
        return sourceName(account, id)
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

    suspend fun candles(symbol: String, timeframe: Timeframe, from: Long, to: Long): List<Candle> {
        val (account, id) = resolve(symbol)
        val period = if (timeframe == Timeframe.H2) Timeframe.H1 else timeframe
        require(CTraderTrendbars.period(period) != null) { "Unsupported cTrader timeframe" }
        require(from >= 0L && to >= from && to <= System.currentTimeMillis()) { "Invalid closed candle range" }
        val interval = period.minutes * 60_000L
        val sourceTo = if (timeframe == Timeframe.H2) to + 3_600_000L else to
        // The gateway supports up to 1,000 bars and 90 days per request.
        val maxWindow = minOf(999L * interval, 90L * 24 * 60 * 60_000L)
        val result = ArrayList<Candle>()
        var start = from
        while (start <= sourceTo) {
            val end = minOf(sourceTo, start + maxWindow)
            val url = "/v1/candles?accountId=$account&symbolId=$id&period=${period.code}" +
                "&from=$start&to=$end&count=1000"
            val json = request(url)
            if (resolve(symbol) != (account to id)) throw IOException("cTrader account changed during history request")
            require(json.optString("source") == "ctrader" && json.optString("symbolId") == id.toString() &&
                json.optString("period") == period.code) { "Wrong cTrader history source" }
            if (json.optBoolean("hasMore")) throw IOException("Incomplete cTrader history page")
            val array = json.getJSONArray("candles")
            for (i in 0 until array.length()) {
                val bar = array.getJSONObject(i)
                val openTime = bar.getLong("timestamp")
                val candle = Candle(symbol, period, openTime, openTime + interval,
                    bar.getDouble("open"), bar.getDouble("high"), bar.getDouble("low"),
                    bar.getDouble("close"), bar.getDouble("volume"), sourceName(account, id))
                if (openTime in start..end && candle.closeTime <= System.currentTimeMillis()) {
                    require(DataIntegrityValidator.validateCandle(candle).isValid) { "Corrupt cTrader candle" }
                    result.add(candle)
                }
            }
            if (end == sourceTo) break
            start = end + interval
        }
        val verified = HistoricalCandleIntegrity.validate(result.sortedBy { it.openTime },
            from, sourceTo + interval, expectedSymbol = symbol, expectedTimeframe = period)
        if (timeframe != Timeframe.H2) return verified
        // H2 isn't native on cTrader. Only fully paired, consecutive H1 bars form an H2 candle.
        return verified.groupBy { it.openTime / 7_200_000L }.values.mapNotNull { bars ->
            if (bars.size != 2 || bars[1].openTime - bars[0].openTime != 3_600_000L ||
                bars[0].openTime % 7_200_000L != 0L) null
            else Candle(symbol, Timeframe.H2, bars[0].openTime, bars[1].closeTime,
                bars[0].open, maxOf(bars[0].high, bars[1].high), minOf(bars[0].low, bars[1].low),
                bars[1].close, bars.sumOf { it.volume }, sourceName(account, id))
        }
    }

    private fun resolve(symbol: String): Pair<String, Long> = synchronized(lock) {
        require(symbol in VerifiedMarketQuote.forexSymbols) { "Not a cTrader forex/metal symbol" }
        if (session.isBlank() || selectedId.isBlank()) throw IOException("اربط حساب cTrader في الإعدادات")
        val id = symbolIds[symbol] ?: throw IOException("الرمز $symbol غير متاح لدى وسيط cTrader")
        selectedId to id
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
        client.newCall(builder.build()).execute().use { response ->
            if (!response.isSuccessful) {
                val body = response.body?.string()?.take(2048).orEmpty()
                val code = runCatching { JSONObject(body).optString("error") }.getOrNull()
                throw CTraderGatewayException(response.code, code)
            }
            val content = response.body?.string() ?: throw IOException("Empty cTrader response")
            if (content.length > 2_000_000) throw IOException("Oversized cTrader response")
            val json = JSONObject(content)
            response.header("X-TradeLab-Session")?.let { newToken ->
                if (newToken.isNotBlank() && newToken.length <= 6144) synchronized(lock) {
                    // A slow request cannot overwrite the session after logout/account change.
                    if (session == token) { session = newToken; persist() }
                }
            }
            json
        }
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
