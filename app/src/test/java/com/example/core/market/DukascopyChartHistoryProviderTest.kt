package com.example.core.market

import com.example.core.model.Timeframe
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.CancellationException
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TemporaryFolder
import org.tukaani.xz.LZMA2Options
import org.tukaani.xz.LZMAOutputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.Instant

class DukascopyChartHistoryProviderTest {
    @get:Rule val temp = TemporaryFolder()
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
    @Test fun absentCompletedYearDoesNotExpandIntoThousandsOfMinuteRequests() = runBlocking {
        var requests = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(404).message("Missing")
                .body(byteArrayOf().toResponseBody()).build()
        }.build()
        val candles = DukascopyChartHistoryProvider(client).fetch("XAUUSD", Timeframe.D1, day, day)
        assertTrue(candles.isEmpty())
        assertEquals(1, requests)
    }
    @Test fun transientArchiveServiceFailureRetriesThenReturnsVerifiedCandles() = runBlocking {
        var requests = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(if (requests == 1) 503 else 200).message("Fixture")
                .body(if (requests == 1) byteArrayOf().toResponseBody() else compressed(listOf(0,60)).toResponseBody()).build()
        }.build()
        val bars = DukascopyChartHistoryProvider(client).fetch("XAUUSD", Timeframe.M1, day, day+60_000)
        assertEquals(2, bars.size)
        assertEquals(2, requests)
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

    @Test fun archiveSurvivesProviderRecreationAndIsReusedAcrossTimeframes() = runBlocking {
        var requests = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(compressed(listOf(0,60,120,180,240,300)).toResponseBody()).build()
        }.build()
        val directory = temp.newFolder()
        DukascopyChartHistoryProvider(client, directory).fetch("XAUUSD", Timeframe.M1, day, day+300_000)
        val offline = OkHttpClient.Builder().addInterceptor { throw java.io.IOException("Offline") }.build()
        val bars = DukascopyChartHistoryProvider(offline, directory).fetch("XAUUSD", Timeframe.M3, day, day+180_000)
        assertEquals(2, bars.size)
        assertEquals(1, requests)
        // Damaged local files must be discarded and verified network bytes fetched again.
        directory.listFiles()!!.single().writeBytes(byteArrayOf(1,2,3))
        assertEquals(2, DukascopyChartHistoryProvider(client, directory).fetch("XAUUSD", Timeframe.M1, day, day+60_000).size)
        assertEquals(2, requests)
    }

    @Test fun socketFailureRecoversButPageDeadlineRemainsAnError() = runBlocking {
        var requests = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            if (requests == 1) throw java.net.SocketTimeoutException("Fixture")
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(compressed(listOf(0,60)).toResponseBody()).build()
        }.build()
        assertEquals(2, DukascopyChartHistoryProvider(client).fetch("XAUUSD", Timeframe.M1, day, day+60_000).size)
        assertEquals(2, requests)
        val failing = OkHttpClient.Builder().addInterceptor { throw java.net.SocketTimeoutException("Fixture") }.build()
        try {
            DukascopyChartHistoryProvider(failing, pageTimeoutMillis=50).fetch("XAUUSD",Timeframe.M1,day,day)
            fail("Deadline must not be an empty trading session")
        } catch (_: MarketDataRequestException) { }
    }

    @Test fun simultaneousPagesShareVerifiedArchiveAndCallerCanCancel() = runBlocking {
        val requests = java.util.concurrent.atomic.AtomicInteger()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests.incrementAndGet()
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(compressed(listOf(0,60)).toResponseBody()).build()
        }.build()
        val provider = DukascopyChartHistoryProvider(client)
        (1..5).map { async { provider.fetch("XAUUSD",Timeframe.M1,day,day+60_000) } }.awaitAll()
        assertEquals(1, requests.get())
        val failing = DukascopyChartHistoryProvider(OkHttpClient.Builder().addInterceptor {
            throw java.net.SocketTimeoutException("Fixture")
        }.build())
        val job = async { failing.fetch("XAUUSD",Timeframe.M1,day,day) }
        delay(50)
        job.cancel()
        try { job.await(); fail("Caller cancellation must propagate") } catch (_: CancellationException) { }
        Unit
    }

    @Test fun diskCacheEvictsOldestAndIgnoresOversizedFiles() {
        val directory = temp.newFolder()
        val disk = ChartArchiveDiskCache(directory, maxBytes=8)
        disk.write("first", byteArrayOf(1,2,3,4))
        directory.listFiles()!!.single().setLastModified(1)
        disk.write("second", byteArrayOf(5,6,7,8))
        disk.write("third", byteArrayOf(9,10,11,12))
        assertNull(disk.read("first"))
        assertArrayEquals(byteArrayOf(5,6,7,8), disk.read("second"))
        assertTrue(directory.listFiles()!!.sumOf { it.length() } <= 8L)
        disk.write("oversized", ByteArray(200_001))
        assertNull(disk.read("oversized"))
    }
}
