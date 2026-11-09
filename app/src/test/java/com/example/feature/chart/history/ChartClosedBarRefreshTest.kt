package com.example.feature.chart.history

import com.example.core.market.HistoricalCandleBoundary
import com.example.core.model.Timeframe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChartClosedBarRefreshTest {
    @Test fun binanceWeeklyRefreshStillUsesExactlyOneCompletedMondayCandle() {
        val week = 604_800_000L
        val now = 345_600_000L + 8L * week + 86_400_000L
        val window = ChartClosedBarRefresh.window(now, Timeframe.W1, brokerTimed = false)
        assertEquals(345_600_000L + 7L * week, window.from)
        assertEquals(window.from, window.to)
        assertEquals(window.to, window.attemptKey)
    }

    @Test fun brokerH4DailyWeeklyRefreshIncludesRealOffGridOpenTimestamps() {
        val now = 30L * 86_400_000L + 23L * 3_600_000L + 37L * 60_000L
        for (frame in listOf(Timeframe.H4, Timeframe.D1, Timeframe.W1)) {
            val interval = frame.minutes * 60_000L
            val window = ChartClosedBarRefresh.window(now, frame, brokerTimed = true)
            val offGridBar = window.to - interval + 60_000L
            assertEquals(window.to - 2L * interval, window.from)
            assertEquals(0L, window.to % 60_000L)
            assertTrue(offGridBar in window.from..window.to)
            assertTrue(Math.floorMod(offGridBar, interval) != 0L)
            assertTrue(window.to + interval <= now)
        }
    }

    @Test fun brokerRefreshIsThrottledByTimeframeInsteadOfPollingEveryTenSeconds() {
        val now = 1_730_000_000_000L
        for (frame in Timeframe.values()) {
            val first = ChartClosedBarRefresh.window(now, frame, brokerTimed = true)
            val second = ChartClosedBarRefresh.window(now + 10_000L, frame, brokerTimed = true)
            assertEquals("$frame should not start a new network retry bucket in 10 seconds",
                first.attemptKey, second.attemptKey)
        }
        val atMinute = Math.floorDiv(now, 60_000L) * 60_000L
        val beforeMinute = ChartClosedBarRefresh.window(atMinute - 1L, Timeframe.M1, true)
        val afterMinute = ChartClosedBarRefresh.window(atMinute, Timeframe.M1, true)
        assertTrue(beforeMinute.attemptKey != afterMinute.attemptKey)
    }

    @Test fun neitherSourceRequestsTheStillFormingBar() {
        val now = 1_730_000_000_000L
        for (frame in Timeframe.values()) {
            val interval = frame.minutes * 60_000L
            val broker = ChartClosedBarRefresh.window(now, frame, brokerTimed = true)
            val exchange = ChartClosedBarRefresh.window(now, frame, brokerTimed = false)
            assertTrue(broker.to + interval <= now)
            assertEquals(HistoricalCandleBoundary.currentOpen(now, interval) - interval, exchange.to)
            assertTrue(exchange.to + interval <= now)
        }
    }
}
