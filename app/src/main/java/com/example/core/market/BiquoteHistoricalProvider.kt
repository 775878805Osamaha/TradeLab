package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Response
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import java.time.Instant
import java.util.concurrent.TimeUnit

/**
 * Keyless, real OHLC history for forex/metals. No synthetic prices.
 * The provider returns newest-first bars; unfinished bars are discarded.
 * Intended for chart/research, never for executable bid/ask.
 */
class BiquoteHistoricalProvider(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS)
        .build()
) {
    fun supports(symbol: String) = symbol in setOf(
        "XAUUSD", "XAGUSD", "EURUSD", "GBPUSD", "USDJPY", "USDCHF",
        "AUDUSD", "USDCAD", "NZDUSD", "EURJPY", "GBPJPY", "EURGBP"
    )

    private fun interval(tf: Timeframe): String = when (tf.minutes) {
        1 -> "1m"
        5 -> "5m"
        15 -> "15m"
        30 -> "30m"
        60 -> "1h"
        240 -> "4h"
        1440 -> "1d"
        else -> throw IOException("Biquote does not support ${tf.minutes}-minute bars")
    }

    private fun bucket(t: Long, minutes: Int): Long {
        val period = minutes * 60_000L
        val offset = if (minutes == 10080) 4L * 86_400_000L else 0L
        return Math.floorDiv(t - offset, period) * period + offset
    }

    suspend fun fetch(symbol: String, tf: Timeframe, from: Long, to: Long): List<Candle> =
        withContext(Dispatchers.IO) {
            require(supports(symbol)) { "Unsupported keyless historical symbol" }
            // A single closed candle is a valid historical page when paging
            // across sparse sessions or near the provider's history boundary.
            require(from >= 0L && to >= from) { "Invalid historical range" }
            val period = tf.minutes.toLong() * 60_000L
            require(period > 0 && to <= System.currentTimeMillis() - period) {
                "Historical range includes unfinished candles"
            }
            val baseMinutes = when (tf.minutes) { 3 -> 1; 120 -> 60; 10080 -> 1440; else -> tf.minutes }
            val basePeriod = baseMinutes * 60_000L
            val baseFrom = if (baseMinutes != tf.minutes) bucket(from, tf.minutes) else from
            val requestedBars = (to - baseFrom) / basePeriod + 2L
            require(requestedBars in 1L..1000L) {
                "Biquote supports at most 1000 source bars per request; shorten the history range"
            }
            val bars = requestedBars.toInt()
            val url = okhttp3.HttpUrl.Builder()
                .scheme("https").host("biquote.io")
                .addPathSegment("api").addPathSegment(symbol).addPathSegment("ohlc")
                .addQueryParameter("interval", when (baseMinutes) { 1 -> "1m"; 60 -> "1h"; 1440 -> "1d"; else -> interval(tf) })
                .addQueryParameter("limit", bars.toString())
                .addQueryParameter("from", Instant.ofEpochMilli(baseFrom).toString())
                .addQueryParameter("to", Instant.ofEpochMilli(to + period).toString())
                .build()
            val body = fetchBody(client, Request.Builder().url(url).build(), "Biquote")
            val root = JSONObject(body)
            if (root.optString("symbol") != symbol) throw IOException("Biquote symbol mismatch")
            val items = root.optJSONArray("bars") ?: throw IOException("Biquote bars missing")
            val candles = ArrayList<Candle>(items.length())
            for (i in 0 until items.length()) {
                val row = items.getJSONObject(i)
                if (row.optBoolean("isOpen", false)) continue
                val openTime = Instant.parse(row.getString("openTime")).toEpochMilli()
                // Providers may include surrounding bars despite the
                // requested from/to filter. Never import those bars into the
                // chart; ignore them and validate the retained range below.
                if (openTime < baseFrom || openTime > to) continue
                if (openTime + basePeriod > System.currentTimeMillis()) continue
                val open = row.getDouble("open")
                val high = row.getDouble("high")
                val low = row.getDouble("low")
                val close = row.getDouble("close")
                val volume = row.optDouble("tickVolume", 0.0)
                if (!open.isFinite() || !high.isFinite() || !low.isFinite() ||
                    !close.isFinite() || low <= 0 || high < low ||
                    open !in low..high || close !in low..high || !volume.isFinite() || volume < 0
                ) throw IOException("Invalid Biquote OHLC bar")
                candles.add(Candle(
                    symbol = symbol, timeframe = tf,
                    openTime = openTime, closeTime = openTime + basePeriod,
                    open = open, high = high, low = low, close = close,
                    volume = volume, source = "BIQUOTE_HISTORICAL"
                ))
            }
            if (candles.map { it.openTime }.toSet().size != candles.size) {
                throw IOException("Biquote returned duplicate historical bars")
            }
            candles.sortBy { it.openTime }
            val result = if (baseMinutes == tf.minutes) candles else
                candles.groupBy { bucket(it.openTime, tf.minutes) }.toSortedMap()
                    .mapNotNull { (start, group) ->
                        val sorted = group.sortedBy { it.openTime }
                        val count = tf.minutes / baseMinutes
                        if (start < from || start > to || sorted.size != count ||
                            sorted.indices.any { i -> sorted[i].openTime != start + i * basePeriod }
                        ) null else Candle(
                            symbol = symbol, timeframe = tf, openTime = start,
                            closeTime = start + period, open = sorted.first().open,
                            high = sorted.maxOf { it.high }, low = sorted.minOf { it.low },
                            close = sorted.last().close, volume = sorted.sumOf { it.volume },
                            source = "BIQUOTE_HISTORICAL"
                        )
                    }
            // A one-candle verified response is still useful for incremental
            // chart paging. Do not turn legitimate sparse market sessions into
            // a blank chart; integrity validation below still checks every bar.
            if (result.isEmpty()) return@withContext emptyList<Candle>()
            // Session gaps (weekends/holidays) are legitimate, but a provider
            // response missing the entire beginning or end of a requested
            // window must not masquerade as a complete replay dataset.
            val sessionGapTolerance = if (tf.minutes >= 1440) 4L * 86_400_000L
                else 3L * 86_400_000L
            if (result.first().openTime - from > sessionGapTolerance ||
                to - result.last().openTime > sessionGapTolerance) {
                throw IOException("Biquote returned incomplete historical window; choose fewer bars or another date")
            }
            HistoricalCandleIntegrity.validate(
                result, from, to + period,
                expectedSource = "BIQUOTE_HISTORICAL",
                expectedSymbol = symbol, expectedTimeframe = tf
            )
        }
    private suspend fun fetchBody(client: OkHttpClient, request: Request, providerName: String): String =
        suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) {
                        continuation.resumeWithException(
                            IOException("$providerName historical request failed", e)
                        )
                    }
                }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val body = response.use {
                            if (!it.isSuccessful) throw IOException("$providerName HTTP ${it.code}")
                            it.body?.string() ?: throw IOException("Empty $providerName response")
                        }
                        if (continuation.isActive) continuation.resume(body)
                    } catch (e: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(e)
                    }
                }
            })
        }

}
