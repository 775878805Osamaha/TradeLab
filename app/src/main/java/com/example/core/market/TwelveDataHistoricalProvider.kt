package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit

/**
 * Authenticated Twelve Data historical candles for forex and spot gold.
 * The key stays in memory and is never logged, persisted or committed.
 * A provider error, missing bars, or unsupported interval fails explicitly.
 */
class TwelveDataHistoricalProvider(
    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()
) {
    private val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    private val queryFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")

    fun supports(symbol: String): Boolean = symbol in setOf(
        "XAUUSD", "XAGUSD", "EURUSD", "GBPUSD", "USDJPY", "USDCHF",
        "AUDUSD", "USDCAD", "NZDUSD", "EURJPY", "GBPJPY", "EURGBP"
    )

    private fun interval(timeframe: Timeframe): String = when (timeframe.minutes) {
        1 -> "1min"
        5 -> "5min"
        15 -> "15min"
        30 -> "30min"
        60 -> "1h"
        120 -> "2h"
        240 -> "4h"
        480 -> "8h"
        1440 -> "1day"
        10080 -> "1week"
        else -> throw IllegalArgumentException("Twelve Data does not support this timeframe")
    }

    suspend fun fetch(
        symbol: String, timeframe: Timeframe, from: Long, to: Long, apiKey: String
    ): List<Candle> = withContext(Dispatchers.IO) {
        require(supports(symbol)) { "Unsupported Twelve Data instrument" }
        require(apiKey.isNotBlank()) { "Twelve Data API key is required" }
        require(from >= 0L && to > from) { "Invalid historical range" }
        val intervalMillis = timeframe.minutes * 60_000L
        require((to - from) / intervalMillis + 1 <= 5000) { "Maximum 5000 candles per request" }
        val providerSymbol = symbol.substring(0, 3) + "/" + symbol.substring(3)
        val start = LocalDateTime.ofEpochSecond(from / 1000L, 0, ZoneOffset.UTC).format(queryFormatter)
        val end = LocalDateTime.ofEpochSecond(to / 1000L, 0, ZoneOffset.UTC).format(queryFormatter)
        val url = okhttp3.HttpUrl.Builder()
            .scheme("https").host("api.twelvedata.com").addPathSegment("time_series")
            .addQueryParameter("symbol", providerSymbol)
            .addQueryParameter("interval", interval(timeframe))
            .addQueryParameter("start_date", start)
            .addQueryParameter("end_date", end)
            .addQueryParameter("timezone", "UTC")
            .addQueryParameter("apikey", apiKey)
            .build()
        // Never place this URL (which contains a credential) in logs or error messages.
        val request = Request.Builder().url(url).header("User-Agent", "TradeLab/2.0").build()
        val payload = httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Twelve Data HTTP ${response.code}")
            response.body?.string() ?: throw IOException("Empty Twelve Data response")
        }
        val root = JSONObject(payload)
        if (root.optString("status") == "error" || root.has("code")) {
            throw IOException("Twelve Data rejected the request (check API key, quota and plan)")
        }
        val values = root.optJSONArray("values")
            ?: throw IOException("No historical candles returned for $symbol")
        val parsed = ArrayList<Candle>(values.length())
        for (i in 0 until values.length()) {
            val row = values.getJSONObject(i)
            val timestamp = row.getString("datetime")
            val openTime = if (timestamp.length == 10) {
                java.time.LocalDate.parse(timestamp).atStartOfDay().toEpochSecond(ZoneOffset.UTC) * 1000L
            } else {
                LocalDateTime.parse(timestamp.replace('T', ' '), formatter)
                    .toEpochSecond(ZoneOffset.UTC) * 1000L
            }
            // Ignore out-of-range rows, never fabricate missing candles.
            if (openTime < from || openTime > to) continue
            val open = row.getString("open").toDouble()
            val high = row.getString("high").toDouble()
            val low = row.getString("low").toDouble()
            val close = row.getString("close").toDouble()
            val volume = row.optString("volume").toDoubleOrNull() ?: 0.0
            parsed.add(Candle(
                symbol = symbol, timeframe = timeframe,
                openTime = openTime, closeTime = openTime + intervalMillis,
                open = open, high = high, low = low, close = close, volume = volume,
                source = "TWELVE_DATA_HISTORICAL"
            ))
        }
        HistoricalCandleIntegrity.validate(
            parsed, from, to + intervalMillis,
            expectedSource = "TWELVE_DATA_HISTORICAL",
            expectedSymbol = symbol, expectedTimeframe = timeframe
        ).also {
            if (it.size < 2) throw IOException("Insufficient Twelve Data history for $symbol")
        }
    }
}
