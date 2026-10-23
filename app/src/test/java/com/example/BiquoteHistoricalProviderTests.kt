package com.example

import com.example.core.market.BiquoteHistoricalProvider
import com.example.core.model.Timeframe
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.IOException
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = android.app.Application::class)
class BiquoteHistoricalProviderTests {
    private val from = Instant.parse("2026-01-05T00:00:00Z").toEpochMilli()
    private val step = 60_000L

    private fun bar(timestamp: String, price: Int = 2000): String =
        """{"openTime":"$timestamp","open":$price,"high":${price + 2},"low":${price - 2},"close":${price + 1},"tickVolume":10,"isOpen":false}"""

    private fun response(symbol: String = "XAUUSD", bars: String): String =
        """{"symbol":"$symbol","bars":[$bars]}"""

    private fun provider(payload: String): BiquoteHistoricalProvider {
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK").body(payload.toResponseBody()).build()
        }.build()
        return BiquoteHistoricalProvider(client)
    }

    @Test fun acceptsRealOrderedHistoricalCandles() = runBlocking {
        val data = response(bars = bar("2026-01-05T00:01:00Z") + "," + bar("2026-01-05T00:00:00Z"))
        val candles = provider(data).fetch("XAUUSD", Timeframe.M1, from, from + step)
        assertEquals(2, candles.size)
        assertEquals(listOf(from, from + step), candles.map { it.openTime })
        assertTrue(candles.all { it.source == "BIQUOTE_HISTORICAL" })
    }

    @Test fun rejectsDuplicateProviderTimestamps() = runBlocking {
        val data = response(bars = bar("2026-01-05T00:00:00Z") + "," + bar("2026-01-05T00:00:00Z"))
        try {
            provider(data).fetch("XAUUSD", Timeframe.M1, from, from + step)
            fail("Duplicate bars must fail")
        } catch (expected: IOException) {
            assertTrue(expected.message!!.contains("duplicate", ignoreCase = true))
        }
    }

    @Test fun rejectsProviderRowsOutsideRequestedWindow() = runBlocking {
        val data = response(bars = bar("2026-01-04T23:59:00Z") + "," + bar("2026-01-05T00:00:00Z"))
        try {
            provider(data).fetch("XAUUSD", Timeframe.M1, from, from + step)
            fail("Out-of-range bars must fail")
        } catch (expected: IOException) {
            assertTrue(expected.message!!.contains("outside", ignoreCase = true))
        }
    }

    @Test fun rejectsTruncatedRequestsBeforeNetwork() = runBlocking {
        val provider = provider(response(bars = ""))
        try {
            provider.fetch("XAUUSD", Timeframe.M1, from, from + 1001 * step)
            fail("Oversized request must fail")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message!!.contains("1000"))
        }
    }

    @Test fun rejectsFutureWindowBeforeNetwork() = runBlocking {
        val provider = provider(response(bars = ""))
        val now = System.currentTimeMillis()
        try {
            provider.fetch("XAUUSD", Timeframe.M1, now - 2 * step, now)
            fail("Unfinished candle request must fail")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message!!.contains("unfinished"))
        }
    }
}
