package com.example.feature.chart.history

import com.example.core.market.HistoricalCandleBoundary
import com.example.core.market.MarketDataRequestException
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.feature.chart.model.ChartViewport
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class ChartHistoryPagingTest {
    private fun bar(tf: Timeframe, at: Long, close: Double = 100.0) = Candle(
        symbol = "XAUUSD", timeframe = tf, openTime = at, closeTime = at + tf.minutes * 60_000L,
        open = 100.0, high = 102.0, low = 99.0, close = close, volume = 1.0,
        source = "TEST_FIXTURE")

    @Test fun timestampPagingPasses100000BarsAndLiveUpdatesRetainThemForEveryTimeframe() = runBlocking {
        for (tf in Timeframe.entries) {
            val interval = tf.minutes * 60_000L
            // Deliberately synthetic fixture: verifies scale/arithmetic, not provider coverage.
            val origin = HistoricalCandleBoundary.currentOpen(10 * interval, interval)
            var bars = listOf(bar(tf, origin + 110_000 * interval))
            var requests = 0
            repeat(201) {
                val page = ChartHistoryPaging.before("XAUUSD", tf, bars.first().openTime) { from, to ->
                    requests++
                    assertEquals(500, ((to - from) / interval + 1).toInt())
                    List(500) { bar(tf, from + it * interval) }
                }
                bars = ChartHistoryPaging.merge(bars, page)
            }
            assertEquals(100_501, bars.size)
            assertEquals(201, requests)
            val last = bars.last()
            bars = ChartHistoryPaging.merge(bars, listOf(last.copy(close = 101.0)))
            assertEquals(100_501, bars.size)
            assertEquals(101.0, bars.last().close, 0.0)
            bars = ChartHistoryPaging.merge(bars, listOf(bar(tf, last.openTime + interval)))
            assertEquals(100_502, bars.size)
            assertTrue(bars.zipWithNext().all { (a, b) -> a.openTime < b.openTime })
            val oldestWindow = ChartViewport.window(bars.size, 600f, 12f, Float.MAX_VALUE)
            assertEquals(0, oldestWindow.startIndex)
        }
    }

    @Test fun closedSessionsScanContiguousWindowsAndNeverInventCandles() = runBlocking {
        val tf = Timeframe.M1
        val interval = 60_000L
        val oldest = 20_000 * interval
        val ranges = mutableListOf<Pair<Long, Long>>()
        val page = ChartHistoryPaging.before("XAUUSD", tf, oldest) { from, to ->
            ranges.add(from to to)
            if (ranges.size < 6) emptyList() else listOf(bar(tf, to))
        }
        assertEquals(6, ranges.size)
        assertTrue(ranges.zipWithNext().all { (newer, older) -> older.second + interval == newer.first })
        assertEquals(1, page.size)
    }

    @Test fun outageCancellationAndInvalidPricesCannotSkipHistory() = runBlocking {
        for (failure in listOf(MarketDataRequestException("HTTP 429"), CancellationException("stop"))) {
            var requests = 0
            try {
                ChartHistoryPaging.before("XAUUSD", Timeframe.M1, 20_000 * 60_000L) { _, _ ->
                    requests++; throw failure
                }
                fail("Failure must propagate")
            } catch (actual: Exception) { assertSame(failure, actual) }
            assertEquals(1, requests)
        }
        var requests = 0
        try {
            ChartHistoryPaging.before("XAUUSD", Timeframe.M1, 20_000 * 60_000L) { from, _ ->
                requests++; listOf(bar(Timeframe.M1, from).copy(low = -1.0))
            }
            fail("Malformed prices must fail")
        } catch (_: IllegalArgumentException) { }
        assertEquals(1, requests)
    }

    @Test fun partialProviderRetriesDoNotJumpOverUnverifiedWindows() = runBlocking {
        var requests = 0
        try {
            ChartHistoryPaging.before("XAUUSD", Timeframe.M1, 20_000 * 60_000L) { _, _ ->
                requests++
                if (requests == 1) throw IOException("incomplete historical window")
                emptyList()
            }
            fail("Smaller empty retries do not prove the full page empty")
        } catch (_: IOException) { }
        assertEquals(4, requests)
    }

    @Test fun appendingOlderHistoryKeepsExistingViewportAnchored() {
        val tf = Timeframe.M1
        val bars = List(500) { bar(tf, (1_000L + it) * 60_000) }
        val before = ChartViewport.window(bars.size, 600f, 12f, 4_000f)
        val older = List(500) { bar(tf, (500L + it) * 60_000) }
        val merged = ChartHistoryPaging.merge(bars, older)
        val after = ChartViewport.window(merged.size, 600f, 12f, 4_000f)
        assertEquals(bars[before.startIndex].openTime, merged[after.startIndex].openTime)
        assertEquals(bars[before.endIndex - 1].openTime, merged[after.endIndex - 1].openTime)
    }
}
