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
    @Test fun chartRequestsLastClosedMinuteNotCurrentBar() {
        val now = 185_000L
        val interval = 60_000L
        val lastClosedOpen = HistoricalCandleBoundary.currentOpen(now, interval) - interval
        assertEquals(120_000L, lastClosedOpen)
        assertTrue(HistoricalCandleBoundary.isClosedRange(lastClosedOpen, now, interval))
    }

    @Test fun chartRequestsLastClosedFifteenMinuteBar() {
        val interval = 15L * 60_000L
        val now = 2L * interval + 12_345L
        val lastClosedOpen = HistoricalCandleBoundary.currentOpen(now, interval) - interval
        assertEquals(interval, lastClosedOpen)
        assertTrue(HistoricalCandleBoundary.isClosedRange(lastClosedOpen, now, interval))
    }

    @Test fun chartRequestsPreviousWeeklyMondayOpen() {
        val week = 604_800_000L
        val mondayOffset = 345_600_000L
        val now = mondayOffset + 3L * week + 20_000L
        val lastClosedOpen = HistoricalCandleBoundary.currentOpen(now, week) - week
        assertEquals(mondayOffset + 2L * week, lastClosedOpen)
        assertTrue(HistoricalCandleBoundary.isClosedRange(lastClosedOpen, now, week))
    }

    @Test fun weeklyBoundaryBeforeFirstMondayDoesNotReturnNegativeTime() {
        val week = 604_800_000L
        assertEquals(-259_200_000L, HistoricalCandleBoundary.currentOpen(0L, week))
        assertEquals(-259_200_000L, HistoricalCandleBoundary.currentOpen(345_599_999L, week))
        assertEquals(345_600_000L, HistoricalCandleBoundary.currentOpen(345_600_000L, week))
    }

    @Test fun largeTimestampBoundaryRemainsAlignedAndNeverInFuture() {
        val week = 604_800_000L
        val now = Long.MAX_VALUE
        val open = HistoricalCandleBoundary.currentOpen(now, week)
        assertTrue(open <= now)
        assertTrue(now - open < week)
        assertEquals(345_600_000L % week, Math.floorMod(open, week))
    }

    @Test(expected = IllegalArgumentException::class)
    fun zeroIntervalIsRejected() {
        HistoricalCandleBoundary.currentOpen(60_000L, 0L)
    }

    @Test(expected = IllegalArgumentException::class)
    fun negativeTimeIsRejected() {
        HistoricalCandleBoundary.currentOpen(-1L, 60_000L)
    }

}
