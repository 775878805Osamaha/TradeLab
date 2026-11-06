package com.example.feature.chart.history

import org.junit.Assert.*
import org.junit.Test

class ChartInitialHistoryScanTest {
    private val minute = 60_000L
    private val day = 86_400_000L

    @Test fun initialBrokerLoadCanReachRealCandlesBeyondAFourDayHoliday() {
        val now = 200L * day
        val windows = ChartInitialHistoryScan.windows(now, minute, 250, brokerTimed = true)
        assertEquals(250, windows.first().bars)
        assertTrue(windows.size > 14)
        assertTrue(now - windows[14].to > 4L * day)
        assertTrue(windows.any { it.to <= now - 13L * day })
        assertTrue(windows.size <= 60)
        // All historical slots are covered; not even an off-grid broker open
        // is skipped between adjacent requests.
        assertTrue(windows.zipWithNext().all { (newer, older) ->
            older.to + minute == newer.from && older.from <= older.to
        })
    }

    @Test fun initialLoadUsesSelectedDepthButLaterClosedWindowsAreWider() {
        val windows = ChartInitialHistoryScan.windows(100L * day, minute, 100, brokerTimed = true)
        assertEquals(100, windows[0].bars)
        assertEquals(500, windows[1].bars)
        assertTrue(windows.drop(1).all { it.bars == ChartInitialHistoryScan.HISTORY_WINDOW_BARS })
        assertEquals(windows[0].from - minute, windows[1].to)
    }

    @Test fun cryptoHasOneGridWindowAndDoesNotSearchClosedBrokerSessions() {
        val end = 50L * day
        val tf15 = 15L * minute
        val windows = ChartInitialHistoryScan.windows(end, tf15, 250, brokerTimed = false)
        assertEquals(1, windows.size)
        assertEquals(end, windows.single().to)
        assertEquals(end - 249 * tf15, windows.single().from)
    }

    @Test fun highTimeframesAndEpochBoundsNeverRequestNegativeTimestamps() {
        for (interval in listOf(minute, 4L * 60L * minute, 7L * day)) {
            val windows = ChartInitialHistoryScan.windows(120L * day, interval, 750, brokerTimed = true)
            assertTrue(windows.isNotEmpty())
            assertTrue(windows.size <= 60)
            assertTrue(windows.all { it.from in 0L..it.to && it.to <= 120L * day })
            assertTrue(windows.zipWithNext().all { (a, b) -> a.to > b.to })
        }
    }
}
