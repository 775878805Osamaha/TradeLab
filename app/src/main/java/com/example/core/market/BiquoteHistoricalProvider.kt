package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException
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

    suspend fun fetch(symbol: String, tf: Timeframe, from: Long, to: Long): List<Candle> =
        withContext(Dispatchers.IO) {
            require(supports(symbol)) { "Unsupported keyless historical symbol" }
            val period = tf.minutes * 60_000L
            val bars = ((to - from) / period + 1).coerceIn(1, 1000).toInt()
            val url = okhttp3.HttpUrl.Builder()
                .scheme("https").host("biquote.io")
                .addPathSegment("api").addPathSegment(symbol).addPathSegment("ohlc")
                .addQueryParameter("interval", interval(tf))
                .addQueryParameter("limit", bars.toString())
                .addQueryParameter("from", Instant.ofEpochMilli(from).toString())
                .addQueryParameter("to", Instant.ofEpochMilli(to + period).toString())
                .build()
            val body = client.newCall(Request.Builder().url(url).build()).execute().use { response ->
                if (!response.isSuccessful) throw IOException("Biquote HTTP ${response.code}")
                response.body?.string() ?: throw IOException("Empty Biquote response")
            }
            val root = JSONObject(body)
            if (root.optString("symbol") != symbol) throw IOException("Biquote symbol mismatch")
            val items = root.optJSONArray("bars") ?: throw IOException("Biquote bars missing")
            val candles = ArrayList<Candle>(items.length())
            for (i in 0 until items.length()) {
                val row = items.getJSONObject(i)
                if (row.optBoolean("isOpen", false)) continue
                val openTime = Instant.parse(row.getString("openTime")).toEpochMilli()
                if (openTime < from || openTime > to) continue
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
                    openTime = openTime, closeTime = openTime + period,
                    open = open, high = high, low = low, close = close,
                    volume = volume, source = "BIQUOTE_HISTORICAL"
                ))
            }
            candles.sortBy { it.openTime }
            if (candles.size < 2) throw IOException("Insufficient historical candles from Biquote")
            HistoricalCandleIntegrity.validate(
                candles, from, to + period,
                expectedSource = "BIQUOTE_HISTORICAL",
                expectedSymbol = symbol, expectedTimeframe = tf
            )
        }
}
