package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.*
import org.tukaani.xz.LZMAInputStream
import java.io.ByteArrayInputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.*
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Official archived BID candles. Never substitutes this feed for executable quotes. */
class DukascopyChartHistoryProvider(private val client: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(8, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
    .callTimeout(25, TimeUnit.SECONDS).build()) {
    companion object {
        const val SOURCE = "DUKASCOPY_BID_HISTORY"
        private const val DAY = 86_400_000L
        private val symbols = setOf("XAUUSD", "XAGUSD", "EURUSD", "GBPUSD", "USDJPY", "USDCHF",
            "AUDUSD", "USDCAD", "NZDUSD", "EURJPY", "GBPJPY", "EURGBP")
        fun supports(symbol: String) = symbol in symbols
    }
    // Retain at most 24 immutable decompressed files.
    private val cache = object : LinkedHashMap<String, List<Candle>>(24, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<Candle>>?) = size > 24
    }

    suspend fun fetch(symbol: String, tf: Timeframe, from: Long, to: Long): List<Candle> = withContext(Dispatchers.IO) {
        require(supports(symbol) && from >= 0 && from <= to)
        val interval = tf.minutes * 60_000L
        require(HistoricalCandleBoundary.isClosedRange(to, System.currentTimeMillis(), interval))
        require((to - from) / interval < 1000) { "Archive chart requests must stay bounded" }
        val base = when { tf.minutes < 60 -> Timeframe.M1; tf.minutes < 1440 -> Timeframe.H1; else -> Timeframe.D1 }
        val until = to + interval
        val raw = try { load(symbol, base, from, until, intArrayOf(64)) }
        catch (error: MarketDataRequestException) {
            // Official chart service is an independent transport for the same BID feed.
            // Never switch transports to conceal a rate-limit or integrity failure.
            if (generateSequence<Throwable>(error) { it.cause }.any { it is ArchiveHttpFailure && it.status == 503 }) {
                return@withContext loadChartService(symbol, tf, from, to)
            }
            throw error
        }
        if (raw.isEmpty()) return@withContext loadChartService(symbol, tf, from, to)
        val groups = raw.groupBy { HistoricalCandleBoundary.currentOpen(it.openTime, interval) }
        val result = groups.toSortedMap().mapNotNull { (start, bars) ->
            if (start < from || start > to) null else Candle(symbol, tf, start,
                open = bars.first().open, high = bars.maxOf { it.high }, low = bars.minOf { it.low },
                close = bars.last().close, volume = bars.sumOf { it.volume }, closeTime = start + interval,
                source = SOURCE)
        }
        HistoricalCandleIntegrity.validate(result, from, until, SOURCE, symbol, tf)
    }

    private suspend fun loadChartService(symbol: String, tf: Timeframe, from: Long, to: Long): List<Candle> {
        val base = when (tf) { Timeframe.M3 -> Timeframe.M1; Timeframe.H2 -> Timeframe.H1; Timeframe.W1 -> Timeframe.D1; else -> tf }
        val intervalName = when (base) {
            Timeframe.M1 -> "1MIN"; Timeframe.M5 -> "5MIN"; Timeframe.M15 -> "15MIN"; Timeframe.M30 -> "30MIN"
            Timeframe.H1 -> "1HOUR"; Timeframe.H4 -> "4HOUR"; Timeframe.D1 -> "1DAY"
            else -> throw IOException("Unsupported archive chart interval")
        }
        val step = base.minutes * 60_000L
        val until = to + tf.minutes * 60_000L
        var cursor = from
        val candles = ArrayList<Candle>()
        var requests = 0
        while (cursor < until) {
            currentCoroutineContext().ensureActive()
            require(requests++ < 8) { "Historical chart page request budget exceeded" }
            val count = minOf(1000L, (until - cursor) / step).coerceAtLeast(1L)
            val url = HttpUrl.Builder().scheme("https").host("freeserv.dukascopy.com")
                .addPathSegment("2.0").addPathSegment("index.php")
                .addQueryParameter("path", "chart/json3")
                .addQueryParameter("instrument", symbol.take(3) + "/" + symbol.drop(3))
                .addQueryParameter("interval", intervalName).addQueryParameter("offer_side", "B")
                .addQueryParameter("last_update", cursor.toString()).addQueryParameter("time_direction", "N")
                .addQueryParameter("limit", count.toString()).build()
            val bytes = try { downloadOnce(url.toString()) }
                catch (error: ArchiveHttpFailure) { throw MarketDataRequestException("Historical chart service HTTP ${error.status}", error) }
            if (bytes == null) break
            val text = bytes.toString(Charsets.UTF_8).trim()
            val json = if (text.startsWith("[")) text else {
                require(Regex("[A-Za-z_$][A-Za-z0-9_$]*").matches(text.substringBefore('('))) { "Invalid historical JSONP wrapper" }
                text.substringAfter('(').substringBeforeLast(')')
            }
            val rows = org.json.JSONArray(json)
            if (rows.length() == 0) break
            var last = Long.MIN_VALUE
            var accepted = 0
            for (i in 0 until rows.length()) {
                val row = rows.getJSONArray(i)
                val time = row.getLong(0)
                require(time > last && time >= cursor) { "Unordered historical chart response" }
                last = time
                if (time >= until) continue
                candles.add(Candle(symbol, base, time, closeTime = time + step,
                    open = row.getDouble(1), high = row.getDouble(2), low = row.getDouble(3),
                    close = row.getDouble(4), volume = row.optDouble(5, 0.0), source = SOURCE))
                accepted++
            }
            if (accepted == 0) throw IOException("Chart service returned no candles in the requested historical window")
            if (last >= until - step) break
            cursor = last + step
        }
        val targetStep = tf.minutes * 60_000L
        val result = candles.groupBy { HistoricalCandleBoundary.currentOpen(it.openTime, targetStep) }
            .toSortedMap().map { (start, bars) -> Candle(symbol, tf, start, closeTime = start + targetStep,
                open = bars.first().open, high = bars.maxOf { it.high }, low = bars.minOf { it.low },
                close = bars.last().close, volume = bars.sumOf { it.volume }, source = SOURCE) }
        return HistoricalCandleIntegrity.validate(result, from, until, SOURCE, symbol, tf)
    }

    private suspend fun load(symbol: String, base: Timeframe, from: Long, until: Long, budget: IntArray): List<Candle> {
        var date = Instant.ofEpochMilli(from).atZone(ZoneOffset.UTC).toLocalDate()
        date = when (base) { Timeframe.D1 -> date.withDayOfYear(1); Timeframe.H1 -> date.withDayOfMonth(1); else -> date }
        val result = ArrayList<Candle>()
        while (date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli() < until) {
            currentCoroutineContext().ensureActive()
            val start = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
            val next = when (base) { Timeframe.D1 -> date.plusYears(1); Timeframe.H1 -> date.plusMonths(1); else -> date.plusDays(1) }
            val end = next.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
            val path = when (base) {
                Timeframe.D1 -> "$symbol/${date.year}/BID_candles_day_1.bi5"
                Timeframe.H1 -> String.format(Locale.US, "%s/%d/%02d/BID_candles_hour_1.bi5", symbol, date.year, date.monthValue - 1)
                else -> String.format(Locale.US, "%s/%d/%02d/%02d/BID_candles_min_1.bi5", symbol, date.year, date.monthValue - 1, date.dayOfMonth)
            }
            val cached = synchronized(cache) { cache[path] }
            val records = if (cached != null) cached else {
                require(budget[0]-- > 0) { "Archive page exceeded its request budget; retry a shorter window" }
                val bytes = download("https://datafeed.dukascopy.com/datafeed/$path")
                if (bytes == null) null else decode(bytes, symbol, base, start, end).also { decoded ->
                    // Current files can be extended by the publisher; do not freeze them in cache.
                    if (end < System.currentTimeMillis()) synchronized(cache) { cache[path] = decoded }
                }
            }
            if (records != null) result.addAll(records.filter { it.openTime >= from && it.openTime < until })
            else if (base != Timeframe.M1 && end > System.currentTimeMillis()) {
                // Current monthly/yearly files may not be published yet. Use finer official archives.
                val finer = if (base == Timeframe.D1) Timeframe.H1 else Timeframe.M1
                result.addAll(load(symbol, finer, maxOf(from, start), minOf(until, end), budget))
            }
            require(result.size <= 100_000) { "Archive page exceeds its source-record budget" }
            date = next
        }
        return result.sortedBy { it.openTime }
    }

    /** BI5 OHLC records: seconds, open, close, low, high (uint32), volume (float32). */
    internal fun decode(bytes: ByteArray, symbol: String, base: Timeframe, start: Long, end: Long): List<Candle> {
        val decompressed = LZMAInputStream(ByteArrayInputStream(bytes), 16_384).use {
            readBounded(it, 100_000)
        }
        require(decompressed.size <= 100_000 && decompressed.size % 24 == 0) { "Invalid archive length" }
        val buffer = ByteBuffer.wrap(decompressed).order(ByteOrder.BIG_ENDIAN)
        val scale = if (symbol.startsWith("XAU") || symbol.startsWith("XAG") || symbol.endsWith("JPY")) 1000.0 else 100000.0
        val bars = ArrayList<Candle>()
        while (buffer.remaining() >= 24) {
            val time = start + (buffer.int.toLong() and 0xffffffffL) * 1000L
            val open = (buffer.int.toLong() and 0xffffffffL) / scale
            val close = (buffer.int.toLong() and 0xffffffffL) / scale
            val low = (buffer.int.toLong() and 0xffffffffL) / scale
            val high = (buffer.int.toLong() and 0xffffffffL) / scale
            val volume = buffer.float.toDouble()
            require(time >= start && time < end && volume.isFinite() && volume >= 0) { "Invalid archive record" }
            // Zero-volume flat records are publisher placeholders, not traded candles.
            if (volume == 0.0 && open == close && open == low && open == high) continue
            bars.add(Candle(symbol, base, time, open = open, high = high, low = low, close = close, volume = volume,
                closeTime = time + base.minutes * 60_000L, source = SOURCE))
        }
        return HistoricalCandleIntegrity.validate(bars, start, end, SOURCE, symbol, base)
    }

    private fun readBounded(input: java.io.InputStream, limit: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            require(output.size() + count <= limit) { "Archive body exceeds limit" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private class ArchiveHttpFailure(val status: Int, val retryAfter: Long?) : IOException("Historical archive HTTP $status")

    private suspend fun download(url: String): ByteArray? {
        for (attempt in 0..2) {
            try { return downloadOnce(url) }
            catch (error: ArchiveHttpFailure) {
                // Retry transient service failures only, respecting a short Retry-After.
                if (error.status != 503 || attempt == 2 || (error.retryAfter ?: 0L) > 10L) {
                    throw MarketDataRequestException(error.message ?: "Historical archive unavailable", error)
                }
                kotlinx.coroutines.delay(maxOf(error.retryAfter ?: (attempt + 1L), 1L) * 1000L)
            }
        }
        throw IOException("Historical archive unavailable")
    }

    private suspend fun downloadOnce(url: String): ByteArray? = suspendCancellableCoroutine { continuation ->
        val call = client.newCall(Request.Builder().url(url).header("User-Agent", "TradeLab/3.0 (historical chart research)").header("Accept", "application/octet-stream").build())
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isActive) continuation.resumeWithException(MarketDataRequestException("Historical archive network failure", e))
            }
            override fun onResponse(call: Call, response: Response) {
                try {
                    val bytes = response.use {
                        if (it.code == 404) null else {
                            if (!it.isSuccessful) throw ArchiveHttpFailure(it.code, it.header("Retry-After")?.toLongOrNull())
                            val input = it.body?.byteStream() ?: throw IOException("Empty archive body")
                            val data = readBounded(input, 200_000)
                            require(data.size <= 200_000) { "Archive body exceeds limit" }
                            data
                        }
                    }
                    if (continuation.isActive) continuation.resume(bytes)
                } catch (error: Exception) { if (continuation.isActive) continuation.resumeWithException(error) }
            }
        })
    }
}
