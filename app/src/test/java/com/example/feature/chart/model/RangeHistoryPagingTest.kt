package com.example.feature.chart.model

import org.junit.Assert.*
import org.junit.Test

class RangeHistoryPagingTest {
    private val day = 24L * RangeHistoryPaging.HOUR_MILLIS

    @Test fun progressivelyExtendsRealTickHistoryUpToOneWeek() {
        val end = 100L * day
        var window = RangeHistoryPaging.Window(end, 1)
        window = RangeHistoryPaging.older(window.end, window.hours)
        assertEquals(6, window.hours)
        repeat(27) { window = RangeHistoryPaging.older(window.end, window.hours) }
        assertEquals(168, window.hours)
        assertEquals(end, window.end)
        assertEquals(end - 7 * day, window.start)
    }

    @Test fun afterOneWeekSlidesBackwardWhileNeverExceedingBrokerLimit() {
        val end = 100L * day
        val first = RangeHistoryPaging.older(end, 168)
        val second = RangeHistoryPaging.older(first.end, first.hours)
        assertEquals(168, first.hours)
        assertEquals(6L * RangeHistoryPaging.HOUR_MILLIS, end - first.end)
        assertEquals(12L * RangeHistoryPaging.HOUR_MILLIS, end - second.end)
        assertEquals(7 * day, first.end - first.start)
    }

    @Test fun neverRequestsTicksBeforeEpoch() {
        val lowest = RangeHistoryPaging.MAX_WINDOW_HOURS * RangeHistoryPaging.HOUR_MILLIS + 1L
        assertEquals(lowest, RangeHistoryPaging.older(lowest, 168).end)
        assertEquals(1L, RangeHistoryPaging.Window(lowest, 168).start)
    }

    @Test fun automaticallyPrefetchesEnoughBarsWithoutOverridingUserOrReplay() {
        assertTrue(RangeHistoryPaging.shouldPrefetchMoreBars(12, 6, false, false))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(48, 6, false, false))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(12, 48, false, false))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(12, 6, true, false))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(12, 6, false, true))
    }
}
