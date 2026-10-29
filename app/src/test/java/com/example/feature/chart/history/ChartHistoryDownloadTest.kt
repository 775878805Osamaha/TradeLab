package com.example.feature.chart.history

import com.example.core.market.HistoricalCandleBoundary
import com.example.core.market.MarketDataRequestException
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.runCurrent
import org.junit.Assert.*
import org.junit.Test

class ChartHistoryDownloadTest {
    private fun bar(tf: Timeframe, at: Long) = Candle("XAUUSD",tf,at,
        open=100.0,high=102.0,low=99.0,close=101.0,volume=1.0,
        closeTime=at + tf.minutes*60_000L, source="TEST_FIXTURE")

    @Test fun bulkTargetExceeds100000WithoutPaddingOnEveryTimeframe() = runBlocking {
        // Synthetic scale test only; does not assert real provider coverage.
        for (tf in Timeframe.entries) {
            val interval = tf.minutes*60_000L
            val origin = HistoricalCandleBoundary.currentOpen(interval*120_000,interval)
            var bars = listOf(bar(tf,origin))
            var pages = 0
            val result = ChartHistoryDownload.run(bars, pauseMillis=0,
                fetchBefore = { oldest ->
                    ChartHistoryPaging.before("XAUUSD",tf,oldest) { from,_ ->
                        pages++; List(500) { bar(tf,from+it*interval) }
                    }
                }, append = { bars=ChartHistoryPaging.merge(bars,it) })
            assertEquals(ChartHistoryDownload.Result.TARGET_REACHED,result)
            assertEquals(100_001,bars.size)
            assertEquals(200,pages)
            assertTrue(bars.zipWithNext().all { (a,b) -> a.openTime<b.openTime })
        }
    }

    @Test fun unavailableHistoryReturnsOnlyActualPagesAndDoesNotClaimTargetReached() = runBlocking {
        var bars = listOf(bar(Timeframe.M1,600_000))
        var requests = 0
        val result=ChartHistoryDownload.run(bars,pauseMillis=0,fetchBefore={ oldest ->
            requests++
            if(requests==1) listOf(bar(Timeframe.M1,oldest-60_000)) else emptyList()
        },append={bars=ChartHistoryPaging.merge(bars,it)})
        assertEquals(2,bars.size)
        assertEquals(ChartHistoryDownload.Result.NO_OLDER_PAGE,result)
    }

    @Test fun outageAndCancellationPreserveProgressAndResumeFromOldest() = runBlocking {
        for(failure in listOf(MarketDataRequestException("503"),CancellationException("stop"))) {
            var bars=listOf(bar(Timeframe.M1,600_000))
            var requests=0
            try {
                ChartHistoryDownload.run(bars,pauseMillis=0,fetchBefore={oldest ->
                    if(++requests==2) throw failure
                    listOf(bar(Timeframe.M1,oldest-60_000))
                },append={bars=ChartHistoryPaging.merge(bars,it)})
                fail()
            } catch(actual: Exception) { assertSame(failure,actual) }
            assertEquals(2,bars.size)
            val oldest=bars.first().openTime
            val result=ChartHistoryDownload.run(bars,target=3,pauseMillis=0,fetchBefore={ resumed ->
                assertEquals(oldest,resumed);listOf(bar(Timeframe.M1,resumed-60_000))
            },append={bars=ChartHistoryPaging.merge(bars,it)})
            assertEquals(ChartHistoryDownload.Result.TARGET_REACHED,result)
            assertEquals(3,bars.size)
        }
    }

    @Test fun duplicateOrNonAdvancingPagesCannotInflateProgress() = runBlocking {
        val initial=listOf(bar(Timeframe.M1,600_000))
        for(page in listOf(initial,listOf(bar(Timeframe.M1,540_000),bar(Timeframe.M1,540_000)))) {
            try {
                ChartHistoryDownload.run(initial,pauseMillis=0,fetchBefore={page},append={fail("Invalid page must not be appended")})
                fail()
            } catch(_: IllegalArgumentException) { }
        }
    }

    @Test fun cancellationAtTerminalCallbacksCannotReportCompletion() = runBlocking {
        for (cancelAtAppend in listOf(false,true)) {
            val job=Job()
            var appended=0
            try {
                withContext(job) {
                    ChartHistoryDownload.run(listOf(bar(Timeframe.M1,600_000)),target=2,pauseMillis=0,
                        fetchBefore={oldest ->
                            if(cancelAtAppend) listOf(bar(Timeframe.M1,oldest-60_000))
                            else { job.cancel(); emptyList() }
                        },append={appended+=it.size;job.cancel()})
                    fail("Cancelled download must not return a terminal success or empty-history result")
                }
                fail("Cancellation must propagate")
            } catch (_: CancellationException) {
                assertEquals(if(cancelAtAppend) 1 else 0,appended)
            } finally { job.cancel() }
        }
    }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    @Test fun cancellingDuringPagePauseStopsFurtherRequestsAndKeepsAppendedCandles() = runTest {
        var bars=listOf(bar(Timeframe.M1,600_000))
        var requests=0
        val download=launch {
            ChartHistoryDownload.run(bars,pauseMillis=1000,fetchBefore={oldest ->
                requests++;listOf(bar(Timeframe.M1,oldest-60_000))
            },append={bars=ChartHistoryPaging.merge(bars,it)})
        }
        runCurrent()
        download.cancelAndJoin()
        assertEquals(1,requests)
        assertEquals(2,bars.size)
    }
}
