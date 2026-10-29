package com.example.feature.chart.history

import com.example.core.market.MarketDataRequestException
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException
import javax.net.ssl.SSLHandshakeException

@OptIn(ExperimentalCoroutinesApi::class)
class ChartHistoryRetryTest {
    @Test fun transientFailuresWaitAndRecoverWithinABoundedBudget() = runTest {
        for (error in listOf(SocketTimeoutException("read"), MarketDataRequestException("HistData HTTP 503"),
            MarketDataRequestException("انتهت مهلة تنزيل الأرشيف"), MarketDataRequestException("network failure"))) {
            var requests = 0
            val notices = mutableListOf<ChartHistoryRetry.Status?>()
            val started = testScheduler.currentTime
            val actual = ChartHistoryRetry.run(onRetry = { notices.add(it) }) {
                if (++requests < 3) throw error
                "verified"
            }
            assertEquals("verified", actual)
            assertEquals(3, requests)
            assertEquals(4_000L, testScheduler.currentTime - started)
            assertEquals(listOf(ChartHistoryRetry.Status(1, 2, 1000), ChartHistoryRetry.Status(2, 2, 3000), null), notices)
        }
    }

    @Test fun exhaustedRetriesPreserveTheOriginalFailureAndClearTheNotice() = runTest {
        val original = MarketDataRequestException("Dukascopy HTTP 502")
        var requests = 0
        var notice: ChartHistoryRetry.Status? = null
        try {
            ChartHistoryRetry.run(onRetry = { notice = it }) { requests++; throw original }
            fail()
        } catch (actual: IOException) { assertSame(original, actual) }
        assertEquals(3, requests)
        assertNull(notice)
    }

    @Test fun quotaAuthMalformedDataAndUnclassifiedErrorsNeverRetry() = runTest {
        val failures = listOf(
            MarketDataRequestException("HistData HTTP 429", SocketTimeoutException()),
            MarketDataRequestException("HTTP 403 network failure"),
            MarketDataRequestException("HTTP 401"), MarketDataRequestException("HTTP 404"),
            MarketDataRequestException("network failure", SSLHandshakeException("certificate")),
            IOException("Invalid cache", IllegalArgumentException("Invalid OHLC")),
            IOException("incomplete historical window"), IllegalArgumentException("Invalid OHLC"),
            CancellationException("stop")
        )
        for (failure in failures) {
            var requests = 0
            try {
                ChartHistoryRetry.run(onRetry = { fail("Terminal error must not announce retries") }) {
                    requests++; throw failure
                }
                fail()
            } catch (actual: Exception) { assertSame(failure, actual) }
            assertEquals(1, requests)
        }
        assertEquals(0L, testScheduler.currentTime)
    }

    @Test fun stopDuringBackoffCancelsImmediatelyWithoutAnotherRequest() = runTest {
        var requests = 0
        var notice: ChartHistoryRetry.Status? = null
        val download = launch {
            ChartHistoryRetry.run(onRetry = { notice = it }) {
                requests++; throw SocketTimeoutException("offline")
            }
        }
        runCurrent()
        assertNotNull(notice)
        download.cancelAndJoin()
        assertEquals(1, requests)
        assertEquals(0L, testScheduler.currentTime)
        assertNull(notice)
    }

    @Test fun successfulEmptyWindowDoesNotRetryOrPretendToHaveCandles() = runTest {
        var requests = 0
        val result = ChartHistoryRetry.run(onRetry = { fail() }) { requests++; emptyList<Candle>() }
        assertTrue(result.isEmpty())
        assertEquals(1, requests)
    }

    @Test fun downloadRetriesTheSameCursorAndCommitsEachVerifiedPageOnlyOnce() = runTest {
        fun bar(time: Long) = Candle("XAUUSD", Timeframe.M1, time,
            open=100.0, high=102.0, low=99.0, close=101.0, volume=0.0,
            closeTime=time+60_000L, source="TEST_FIXTURE")
        var bars = listOf(bar(600_000L))
        val cursors = mutableListOf<Long>()
        var appends = 0
        val result = ChartHistoryDownload.run(bars, target=3, pauseMillis=0,
            fetchBefore = { oldest ->
                var attempt = 0
                ChartHistoryRetry.run {
                    cursors.add(oldest)
                    if (++attempt <= 2) throw MarketDataRequestException("HistData HTTP 503")
                    listOf(bar(oldest-60_000L))
                }
            }, append = { page -> appends++; bars=ChartHistoryPaging.merge(bars, page) })
        assertEquals(ChartHistoryDownload.Result.TARGET_REACHED, result)
        assertEquals(listOf(600_000L,600_000L,600_000L,540_000L,540_000L,540_000L), cursors)
        assertEquals(2, appends)
        assertEquals(listOf(480_000L,540_000L,600_000L), bars.map { it.openTime })
    }

    @Test fun appendFailureIsNotRetriedAsANetworkRequest() = runTest {
        val initial = listOf(Candle("XAUUSD", Timeframe.M1, 600_000L,
            open=100.0, high=102.0, low=99.0, close=101.0, volume=0.0,
            closeTime=660_000L, source="TEST_FIXTURE"))
        var requests = 0
        val failure = SocketTimeoutException("append failed")
        try {
            ChartHistoryDownload.run(initial, target=2, pauseMillis=0,
                fetchBefore = { oldest -> ChartHistoryRetry.run {
                    requests++; listOf(initial.single().copy(openTime=oldest-60_000L, closeTime=oldest))
                } }, append = { throw failure })
            fail()
        } catch (actual: IOException) { assertSame(failure, actual) }
        assertEquals(1, requests)
    }
}
