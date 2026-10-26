package com.example.core.market

import com.example.core.model.Tick
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.*
import org.json.JSONObject
import java.io.IOException
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Real broker bid/ask. Never derive executable quotes from a historical close. */
class BiquoteQuoteProvider(private val client: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(6, TimeUnit.SECONDS).readTimeout(8, TimeUnit.SECONDS)
    .callTimeout(12, TimeUnit.SECONDS).build()) {
    suspend fun fetch(symbol: String): Tick {
        require(symbol in VerifiedMarketQuote.forexSymbols)
        val url = HttpUrl.Builder().scheme("https").host("biquote.io").addPathSegment("api")
            .addPathSegment(symbol).addQueryParameter("allowStale", "false").build()
        val request = Request.Builder().url(url).header("User-Agent", "TradeLab/2.0")
            .header("Accept", "application/json").header("Cache-Control", "no-cache").build()
        val body: String = suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, error: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(MarketDataRequestException("Biquote quote network failure: ${error.javaClass.simpleName}", error))
                }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val text = response.use {
                            if (!it.isSuccessful) throw MarketDataRequestException("Biquote quote HTTP ${it.code}; Retry-After=${it.header("Retry-After") ?: "none"}")
                            it.body?.string() ?: throw IOException("Empty Biquote quote")
                        }
                        if (continuation.isActive) continuation.resume(text)
                    } catch (error: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(error)
                    }
                }
            })
        }
        return parse(body, symbol, System.currentTimeMillis())
    }

    internal fun parse(body: String, symbol: String, now: Long): Tick {
        val root = JSONObject(body)
        if (root.getString("symbol") != symbol || symbol !in VerifiedMarketQuote.forexSymbols)
            throw IOException("Biquote quote symbol mismatch")
        if (root.getBoolean("stale") || root.getString("marketState") != "open" ||
            root.getDouble("quoteAgeSeconds").let { !it.isFinite() || it !in 0.0..15.0 })
            throw IOException("Biquote quote is stale or market closed")
        if (!root.getString("source").startsWith("MetaTrader 5")) throw IOException("Unrecognized Biquote broker source")
        val bid = root.getDouble("bid")
        val ask = root.getDouble("ask")
        val timestamp = Instant.parse(root.getString("timestamp")).toEpochMilli()
        // FX last=0 is documented by the provider; mid is derived from REAL bid/ask.
        val tick = Tick(symbol, bid, ask, (bid + ask) / 2.0, timestamp, "BIQUOTE_REST")
        if (!VerifiedMarketQuote.isVerified(tick, symbol, now)) throw IOException("Invalid or expired Biquote bid/ask")
        return tick
    }
}
