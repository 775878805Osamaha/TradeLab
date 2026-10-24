package com.example.feature.backtest

import com.example.core.market.HistoricalCandleBoundary
import org.junit.Assert.*
import org.junit.Test

class BacktestHistoricalWindowTest {
    private val minute = 60_000L

    @Test fun m15RequestUsesCompletedAlignedBars() {
        val interval = 15L * minute
        val now = 1_700_000_123_456L
        val window = BacktestHistoricalWindow.lastClosed(now, interval, 350)
        assertEquals(0L, Math.floorMod(window.first, interval))
        assertEquals(0L, Math.floorMod(window.last, interval))
        assertEquals(350L, (window.last - window.first) / interval + 1L)
        assertTrue(HistoricalCandleBoundary.isClosedRange(window.last, now, interval))
    }

    @Test fun requestExactlyOnBoundaryExcludesCurrentBar() {
        val interval = 3L * minute
        val now = 1_700_000_100_000L - Math.floorMod(1_700_000_100_000L, interval)
        val window = BacktestHistoricalWindow.lastClosed(now, interval, 16)
        assertEquals(now - interval, window.last)
    }

    @Test fun weeklyBarsFollowMondayUtcAlignment() {
        val week = 7L * 24L * 60L * minute
        val now = 1_700_000_000_000L
        val window = BacktestHistoricalWindow.lastClosed(now, week, 16)
        val mondayOffset = 4L * 24L * 60L * minute
        assertEquals(0L, Math.floorMod(window.first - mondayOffset, week))
        assertEquals(0L, Math.floorMod(window.last - mondayOffset, week))
        assertTrue(HistoricalCandleBoundary.isClosedRange(window.last, now, week))
    }

    @Test fun twoHourBarsStayAligned() {
        val interval = 120L * minute
        val window = BacktestHistoricalWindow.lastClosed(1_700_000_000_000L, interval, 350)
        assertEquals(0L, Math.floorMod(window.first, interval))
        assertEquals(0L, Math.floorMod(window.last, interval))
    }

    @Test fun rejectsInvalidAndOverflowingRanges() {
        rejects { BacktestHistoricalWindow.lastClosed(-1, 900_000L, 350) }
        rejects { BacktestHistoricalWindow.lastClosed(100, 900_000L, 350) }
        rejects { BacktestHistoricalWindow.lastClosed(1_700_000_000_000L, 0L, 350) }
        rejects { BacktestHistoricalWindow.lastClosed(1_700_000_000_000L, 900_000L, 15) }
        rejects { BacktestHistoricalWindow.lastClosed(Long.MAX_VALUE, Long.MAX_VALUE / 2, 20_000) }
    }

    private fun rejects(block: () -> Unit) {
        try { block(); fail("Expected invalid window") }
        catch (_: IllegalArgumentException) {}
        catch (_: ArithmeticException) {}
    }
}
