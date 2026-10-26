package com.example

import com.example.core.market.BiquoteHistoricalProvider
import com.example.core.model.Timeframe
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
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
    @Test fun rejectsProviderHistoryMissingBeginningOfRequestedWindow() = runBlocking {
        val data = response(bars = bar("2026-01-05T00:00:00Z") + "," + bar("2026-01-05T01:00:00Z"))
        val fiveDaysEarlier = from - 5L * 86_400_000L
        try {
            // H1 keeps the request below the provider's 1000-bar limit, so
            // this test reaches the missing-window coverage check.
            provider(data).fetch("XAUUSD", Timeframe.H1, fiveDaysEarlier, from + 60L * step)
            fail("A missing history window must not pass")
        } catch (expected: IOException) {
            assertTrue(expected.message!!.contains("outside", ignoreCase = true) ||
                expected.message!!.contains("incomplete", ignoreCase = true))
        }
    }

    @Test fun cancellingHistoryCoroutineCancelsInFlightHttpCall() = runBlocking {
        val started = CountDownLatch(1)
        val cancelled = CountDownLatch(1)
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            started.countDown()
            try {
                // Keep the HTTP call in-flight until coroutine cancellation.
                while (!chain.call().isCanceled()) {
                    Thread.sleep(10)
                }
                cancelled.countDown()
                throw IOException("cancelled")
            } catch (e: InterruptedException) {
                throw IOException("interrupted", e)
            }
        }.build()
        val job = async(Dispatchers.IO) {
            BiquoteHistoricalProvider(client).fetch("XAUUSD", Timeframe.M1, from, from + step)
        }
        assertTrue("HTTP request did not start", withContext(Dispatchers.IO) {
            started.await(5, TimeUnit.SECONDS)
        })
        job.cancelAndJoin()
        assertTrue("HTTP request was not cancelled", withContext(Dispatchers.IO) {
            cancelled.await(5, TimeUnit.SECONDS)
        })
    }

    @Test fun threeMinuteCandleIncludesItsLastTwoMinuteRows() = runBlocking {
        var requestedTo: String? = null
        var requestedLimit: String? = null
        val payload = response(bars = (0..2).joinToString(",") { bar(Instant.ofEpochMilli(from + it * step).toString(), 2000 + it) })
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requestedTo = chain.request().url.queryParameter("to")
            requestedLimit = chain.request().url.queryParameter("limit")
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(payload.toResponseBody()).build()
        }.build()
        val candles = BiquoteHistoricalProvider(client).fetch("XAUUSD", Timeframe.M3, from, from)
        assertEquals(1, candles.size)
        assertEquals(from + 3 * step, candles.single().closeTime)
        assertEquals(2003.0, candles.single().close, .0001)
        assertEquals("2026-01-05T00:02:00Z", requestedTo)
        assertEquals("3", requestedLimit)
    }
    @Test fun directIntervalUsesInclusiveLastOpenNotTheNextCandle() = runBlocking {
        var requestedTo: String? = null
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requestedTo = chain.request().url.queryParameter("to")
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(response(bars = bar("2026-01-05T00:00:00Z")).toResponseBody()).build()
        }.build()
        assertEquals(1, BiquoteHistoricalProvider(client).fetch("XAUUSD", Timeframe.M15, from, from).size)
        assertEquals("2026-01-05T00:00:00Z", requestedTo)
    }
    @Test fun twoHourCandleIncludesBothHourlyRows() = runBlocking {
        val payload = response(bars = bar("2026-01-05T00:00:00Z") + "," + bar("2026-01-05T01:00:00Z", 2001))
        val candles = provider(payload).fetch("XAUUSD", Timeframe.H2, from, from)
        assertEquals(1, candles.size)
        assertEquals(from + 120 * step, candles.single().closeTime)
        assertEquals(2002.0, candles.single().close, .0001)
    }
    @Test fun weeklyForexUsesRealWeekdaysWithoutInventingWeekendBars() = runBlocking {
        val payload = response(bars = (0..4).joinToString(",") { bar(Instant.ofEpochMilli(from + it * 86400000L).toString(), 2000 + it) })
        val candles = provider(payload).fetch("XAUUSD", Timeframe.W1, from, from)
        assertEquals(1, candles.size)
        assertEquals(50.0, candles.single().volume, .0001)
        assertEquals(2005.0, candles.single().close, .0001)
    }
    @Test fun weeklyForexRejectsMissingWeekdayRatherThanFillingIt() = runBlocking {
        val payload = response(bars = listOf(0, 1, 3, 4).joinToString(",") { bar(Instant.ofEpochMilli(from + it * 86400000L).toString()) })
        assertTrue(provider(payload).fetch("XAUUSD", Timeframe.W1, from, from).isEmpty())
    }

}
