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
        .callTimeout(25, TimeUnit.SECONDS)
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
        require(apiKey.length <= 256) { "Twelve Data API key is too long" }
        require(from >= 0L && to >= from) { "Invalid historical range" }
        val intervalMillis = timeframe.minutes.toLong() * 60_000L
        require(intervalMillis > 0L) { "Invalid historical timeframe" }
        require(HistoricalCandleBoundary.currentOpen(from, intervalMillis) == from &&
            HistoricalCandleBoundary.currentOpen(to, intervalMillis) == to) { "Historical range must align to candle opens" }
        if (timeframe == Timeframe.M3) {
            // Twelve Data has no native 3min interval. Read every underlying M1
            // candle, including the last two minutes of the final target bar.
            require((to - from) / intervalMillis + 1 <= 1666) { "Maximum 1666 three-minute candles per request" }
            require(HistoricalCandleBoundary.isClosedRange(to, System.currentTimeMillis(), intervalMillis))
            val minutes = fetch(symbol, Timeframe.M1, from, to + 120_000L, apiKey)
            val bars = minutes.groupBy { HistoricalCandleBoundary.currentOpen(it.openTime, intervalMillis) }
                .toSortedMap().map { (start, rows) ->
                    Candle(symbol, timeframe, start, open = rows.first().open, high = rows.maxOf { it.high },
                        low = rows.minOf { it.low }, close = rows.last().close, volume = rows.sumOf { it.volume },
                        closeTime = start + intervalMillis, source = "TWELVE_DATA_HISTORICAL")
                }
            return@withContext HistoricalCandleIntegrity.validate(bars, from, to + intervalMillis,
                expectedSource = "TWELVE_DATA_HISTORICAL", expectedSymbol = symbol, expectedTimeframe = timeframe)
        }
        require((to - from) / intervalMillis + 1 <= 5000) { "Maximum 5000 candles per request" }
        val now = System.currentTimeMillis()
        require(to <= now - intervalMillis) { "Historical range includes an unfinished candle" }
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
            .addQueryParameter("outputsize", "5000")
            .addQueryParameter("apikey", apiKey)
            .build()
        // Never place this URL (which contains a credential) in logs or error messages.
        val request = Request.Builder().url(url).header("User-Agent", "TradeLab/2.0").build()
        val payload = fetchBody(httpClient, request, "Twelve Data")
        val root = JSONObject(payload)
        if (root.optString("status") == "error" || root.has("code")) {
            throw MarketDataRequestException("Twelve Data rejected the request (check API key, quota and plan)")
        }
        val meta = root.optJSONObject("meta")
            ?: throw IOException("Twelve Data response is missing metadata")
        if (meta.optString("symbol") != providerSymbol || meta.optString("interval") != interval(timeframe)) {
            throw IOException("Twelve Data returned a different symbol or timeframe")
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
            // Reject wrong-range provider rows instead of silently discarding data.
            if (openTime < from || openTime > to) {
                throw IOException("Twelve Data returned a candle outside the requested range")
            }
            val open = row.getString("open").toDouble()
            val high = row.getString("high").toDouble()
            val low = row.getString("low").toDouble()
            val close = row.getString("close").toDouble()
            val volume = if (!row.has("volume") || row.isNull("volume") || row.optString("volume").isBlank()) {
                0.0 // Some spot FX feeds do not provide volume.
            } else {
                row.getString("volume").toDoubleOrNull()
                    ?: throw IOException("Invalid Twelve Data volume for $symbol")
            }
            parsed.add(Candle(
                symbol = symbol, timeframe = timeframe,
                openTime = openTime, closeTime = openTime + intervalMillis,
                open = open, high = high, low = low, close = close, volume = volume,
                source = "TWELVE_DATA_HISTORICAL"
            ))
        }
        // Twelve Data commonly returns newest-first. The integrity validator
        // expects ascending timestamps; normalize before validation.
        parsed.sortBy { it.openTime }
        HistoricalCandleIntegrity.validate(
            parsed, from, to + intervalMillis,
            expectedSource = "TWELVE_DATA_HISTORICAL",
            expectedSymbol = symbol, expectedTimeframe = timeframe
        ).also {
            if (it.size < 2) throw IOException("Insufficient Twelve Data history for $symbol")
            // Detect provider truncation: the response must span the requested
            // starting bar (weekend gaps are allowed, invented bars are not).
            val tolerance = if (timeframe.minutes >= 1440) 4L * 24 * 60 * 60 * 1000
                else 3L * 24 * 60 * 60 * 1000
            if (it.first().openTime - from > tolerance) {
                throw IOException("Twelve Data returned truncated history; choose fewer bars or another date")
            }
        }
    }
    private suspend fun fetchBody(client: OkHttpClient, request: Request, providerName: String): String =
        suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) {
                        continuation.resumeWithException(
                            MarketDataRequestException("$providerName historical request failed", e)
                        )
                    }
                }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val body = response.use {
                            if (!it.isSuccessful) throw MarketDataRequestException("$providerName HTTP ${it.code}")
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
