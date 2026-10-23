package com.example.core.history

import com.example.core.market.DataIntegrityValidator
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import java.io.File
import java.io.IOException
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject

internal enum class HistoryError { KEY, SYMBOL, INTERVAL, RANGE, ACCESS, LIMIT, NETWORK, INVALID, EMPTY }

/** Historical OHLC only. Never used to manufacture a live bid/ask quote. */
class TwelveDataHistory internal constructor(
    private val apiKey: () -> String,
    private val directory: File,
    private val errorText: (HistoryError) -> String,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS).build(),
    private val clock: () -> Long = System::currentTimeMillis
) {
    private val lock = Mutex()
    private fun failure(reason: HistoryError): Nothing = throw IOException(errorText(reason))

    suspend fun load(symbol: String, timeframe: Timeframe, from: Long, to: Long): List<Candle> =
        withContext(Dispatchers.IO) {
            lock.withLock {
                val remote = SYMBOLS[symbol] ?: failure(HistoryError.SYMBOL)
                val interval = INTERVALS[timeframe] ?: failure(HistoryError.INTERVAL)
                val step = timeframe.minutes * 60_000L
                if (from < 0 || from > to || (to - from) / step > 10_000) failure(HistoryError.RANGE)
                // Only completed candles; do not allow an unfinished bar into a backtest.
                val endExclusive = minOf(to, clock()) / step * step
                var cursor = Math.floorDiv(from, step) * step
                if (cursor >= endExclusive) failure(HistoryError.EMPTY)
                directory.mkdirs()
                val result = mutableListOf<Candle>()
                while (cursor < endExclusive) {
                    ensureActive()
                    val end = minOf(endExclusive, cursor + step * 1000L)
                    val cache = File(directory, "${symbol}_${timeframe.code}_${cursor}_${end}.json")
                    val cached = if (cache.exists()) runCatching {
                        parse(cache.readText(), symbol, timeframe, cursor, end)
                    }.getOrNull() else null
                    val candles = cached ?: run {
                        val secret = apiKey().trim()
                        if (secret.isEmpty()) failure(HistoryError.KEY)
                        val url = "https://api.twelvedata.com/time_series".toHttpUrl().newBuilder()
                            .addQueryParameter("symbol", remote)
                            .addQueryParameter("interval", interval)
                            .addQueryParameter("timezone", "UTC")
                            .addQueryParameter("start_date", date(cursor))
                            .addQueryParameter("end_date", date(end - 1))
                            .addQueryParameter("outputsize", "1000")
                            .addQueryParameter("order", "asc")
                            .addQueryParameter("apikey", secret).build()
                        // No HTTP logging interceptor: request URLs contain the API key.
                        val call = client.newCall(Request.Builder().url(url).build())
                        val body = try {
                            call.execute().use { response ->
                                when (response.code) {
                                    401, 403 -> failure(HistoryError.ACCESS)
                                    429 -> failure(HistoryError.LIMIT)
                                }
                                if (!response.isSuccessful) failure(HistoryError.NETWORK)
                                response.body?.string() ?: failure(HistoryError.INVALID)
                            }
                        } catch (cancelled: CancellationException) { throw cancelled }
                        catch (error: IOException) {
                            // Never expose request URLs, credentials, or server response bodies.
                            if (HistoryError.entries.any { error.message == errorText(it) }) throw error
                            failure(HistoryError.NETWORK)
                        }
                        ensureActive()
                        val root = try { JSONObject(body) } catch (_: Exception) { failure(HistoryError.INVALID) }
                        if (root.optString("status") == "error") {
                            failure(when (root.optInt("code")) {
                                401, 403 -> HistoryError.ACCESS
                                429 -> HistoryError.LIMIT
                                else -> HistoryError.EMPTY
                            })
                        }
                        val decoded = try { parse(body, symbol, timeframe, cursor, end) }
                            catch (_: Exception) { failure(HistoryError.INVALID) }
                        val temp = File(directory, cache.name + ".tmp")
                        temp.writeText(body)
                        check(temp.renameTo(cache))
                        pruneCache()
                        decoded
                    }
                    result.addAll(candles)
                    cursor = end
                }
                ensureActive()
                if (result.isEmpty()) failure(HistoryError.EMPTY)
                result.distinctBy { it.openTime }.sortedBy { it.openTime }
            }
        }

    private fun pruneCache() {
        val files = directory.listFiles()?.filter { it.extension == "json" }?.sortedBy { it.lastModified() } ?: return
        var total = files.sumOf { it.length() }
        for (file in files) {
            if (total <= 32L * 1024 * 1024) break
            val size = file.length()
            if (file.delete()) total -= size
        }
    }

    companion object {
        val SYMBOLS = mapOf("XAUUSD" to "XAU/USD", "EURUSD" to "EUR/USD",
            "GBPUSD" to "GBP/USD", "USDJPY" to "USD/JPY")
        // M3 is intentionally rejected: Twelve Data does not offer a native 3min series.
        val INTERVALS = mapOf(Timeframe.M1 to "1min", Timeframe.M5 to "5min",
            Timeframe.M15 to "15min", Timeframe.M30 to "30min", Timeframe.H1 to "1h",
            Timeframe.H2 to "2h", Timeframe.H4 to "4h", Timeframe.D1 to "1day")
        private val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
        private fun date(ms: Long) = formatter.format(Instant.ofEpochMilli(ms).atOffset(ZoneOffset.UTC))

        internal fun parse(body: String, symbol: String, timeframe: Timeframe, from: Long, endExclusive: Long): List<Candle> {
            val root = JSONObject(body)
            require(root.optString("status") != "error")
            val meta = root.getJSONObject("meta")
            require(meta.getString("symbol") == SYMBOLS[symbol])
            require(meta.getString("interval") == INTERVALS[timeframe])
            val values = root.getJSONArray("values")
            require(values.length() <= 1000)
            val step = timeframe.minutes * 60_000L
            val candles = (0 until values.length()).map { index ->
                val row = values.getJSONObject(index)
                val date = row.getString("datetime")
                val time = if (date.length == 10) LocalDate.parse(date).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli()
                    else LocalDateTime.parse(date, formatter).toInstant(ZoneOffset.UTC).toEpochMilli()
                require(time >= from && time < endExclusive && time + step <= endExclusive)
                Candle(symbol = symbol, timeframe = timeframe, openTime = time, closeTime = time + step,
                    open = row.getString("open").toDouble(), high = row.getString("high").toDouble(),
                    low = row.getString("low").toDouble(), close = row.getString("close").toDouble(),
                    // FX/spot gold may not have traded volume. Zero means unavailable here.
                    volume = if (row.isNull("volume")) 0.0 else row.getString("volume").toDouble(),
                    source = "TWELVE_DATA_HISTORICAL").also {
                        require(DataIntegrityValidator.validateCandle(it).isValid)
                    }
            }
            require(candles.map { it.openTime }.distinct().size == candles.size)
            return candles.sortedBy { it.openTime }
        }
    }
}
