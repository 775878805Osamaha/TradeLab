package com.example.core.market

import com.example.core.model.Timeframe
import kotlinx.coroutines.runBlocking
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.tukaani.xz.LZMA2Options
import org.tukaani.xz.LZMAOutputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.Instant

class DukascopyChartHistoryProviderTest {
    private val day = Instant.parse("2025-04-30T00:00:00Z").toEpochMilli()
    private fun compressed(offsets: List<Int>, bad: Boolean = false): ByteArray {
        val buffer = ByteBuffer.allocate(offsets.size * 24).order(ByteOrder.BIG_ENDIAN)
        offsets.forEach { seconds ->
            buffer.putInt(seconds).putInt(3_300_000).putInt(3_301_000)
                .putInt(if (bad) 3_400_000 else 3_299_000).putInt(3_302_000).putFloat(2f)
        }
        val bytes = buffer.array()
        val output = ByteArrayOutputStream()
        LZMAOutputStream(output, LZMA2Options(), bytes.size.toLong()).use { it.write(bytes) }
        return output.toByteArray()
    }
    @Test fun decodesUnsignedPricesFieldOrderAndSource() {
        val bars = DukascopyChartHistoryProvider().decode(compressed(listOf(0, 60, 120)), "XAUUSD", Timeframe.M1, day, day + 86_400_000)
        assertEquals(3, bars.size)
        assertEquals(3300.0, bars.first().open, 0.0)
        assertEquals(3301.0, bars.first().close, 0.0)
        assertEquals(3299.0, bars.first().low, 0.0)
        assertEquals(3302.0, bars.first().high, 0.0)
        assertEquals(2.0, bars.first().volume, 0.0)
        assertEquals(DukascopyChartHistoryProvider.SOURCE, bars.first().source)
    }
    @Test fun malformedDuplicateAndOutOfPeriodRecordsFail() {
        for ((times,bad) in listOf(listOf(0,0) to false, listOf(0) to true, listOf(86_400) to false)) {
            try {
                DukascopyChartHistoryProvider().decode(compressed(times,bad), "XAUUSD", Timeframe.M1, day, day+86_400_000)
                fail("Invalid archive must fail")
            } catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun aggregatesOnlyActualArchivedBarsAndUsesZeroBasedMonth() = runBlocking {
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            assertEquals("/datafeed/XAUUSD/2025/03/30/BID_candles_min_1.bi5", chain.request().url.encodedPath)
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(compressed(listOf(0,60,120)).toResponseBody()).build()
        }.build()
        val candles = DukascopyChartHistoryProvider(client).fetch("XAUUSD", Timeframe.M3, day, day)
        assertEquals(1, candles.size)
        assertEquals(6.0, candles.single().volume, 0.0)
        assertEquals(day+180_000L, candles.single().closeTime)
    }
    @Test fun absentCompletedYearUsesOnlyOneBoundedChartFallback() = runBlocking {
        var requests = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(404).message("Missing")
                .body(byteArrayOf().toResponseBody()).build()
        }.build()
        val candles = DukascopyChartHistoryProvider(client).fetch("XAUUSD", Timeframe.D1, day, day)
        assertTrue(candles.isEmpty())
        assertEquals(2, requests)
    }
    @Test fun officialChartJsonpFallbackPreservesDatePricesAndBidSide() = runBlocking {
        var chartRequests = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val chart = chain.request().url.host == "freeserv.dukascopy.com"
            val body = if (chart) {
                chartRequests++
                assertEquals("B", chain.request().url.queryParameter("offer_side"))
                assertEquals(day.toString(), chain.request().url.queryParameter("last_update"))
                "tradelabHistory([[$day,3300,3302,3299,3301,2],[${day+60_000},3301,3303,3300,3302,3]]);"
            } else "unavailable"
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(if (chart) 200 else 503).message("Fixture").body(body.toByteArray().toResponseBody()).build()
        }.build()
        val bars = DukascopyChartHistoryProvider(client).fetch("XAUUSD", Timeframe.M1, day, day+60_000)
        assertEquals(2, bars.size)
        assertEquals(3301.0, bars.first().close, 0.0)
        assertEquals(1, chartRequests)
    }
    @Test fun rateLimitDoesNotLookLikeMissingHistory() = runBlocking {
        var requests=0
        val client=OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(429).message("Limit")
                .body(byteArrayOf().toResponseBody()).build()
        }.build()
        try { DukascopyChartHistoryProvider(client).fetch("XAUUSD",Timeframe.M1,day,day);fail("429 must propagate") }
        catch (_: MarketDataRequestException) { }
        assertEquals(1,requests)
    }
}
