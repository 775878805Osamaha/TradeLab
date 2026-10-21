package com.example.core.market

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoricalCandleBoundaryTest {
    @Test fun currentMinuteIsExcludedButPreviousMinuteIsAllowed() {
        val now = 185_000L // 3:05 into minute 3
        assertEquals(180_000L, HistoricalCandleBoundary.currentOpen(now, 60_000L))
        assertTrue(HistoricalCandleBoundary.isClosedRange(179_999L, now, 60_000L))
        assertFalse(HistoricalCandleBoundary.isClosedRange(180_000L, now, 60_000L))
    }

    @Test fun weeklyBoundaryUsesMondayUtc() {
        val week = 604_800_000L
        val monday = 345_600_000L
        val now = monday + week + 120_000L
        assertEquals(monday + week, HistoricalCandleBoundary.currentOpen(now, week))
        assertTrue(HistoricalCandleBoundary.isClosedRange(monday, now, week))
        assertFalse(HistoricalCandleBoundary.isClosedRange(monday + week, now, week))
    }
}
