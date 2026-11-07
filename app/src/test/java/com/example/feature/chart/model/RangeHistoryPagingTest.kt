package com.example.feature.chart.model

import com.example.core.market.RangeBarsEngine
import com.example.core.market.RangePriceTick
import org.junit.Assert.*
import org.junit.Test

class RangeHistoryPagingTest {
    private val day = 24L * RangeHistoryPaging.HOUR_MILLIS

    @Test fun initialRangeHistoryAvoidsUnneededMultiHourTickDownloads() {
        assertEquals(1, RangeHistoryPaging.initialWindowHours(50))
        assertEquals(1, RangeHistoryPaging.initialWindowHours(100))
        assertEquals(2, RangeHistoryPaging.initialWindowHours(250))
        assertEquals(3, RangeHistoryPaging.initialWindowHours(500))
        assertEquals(6, RangeHistoryPaging.initialWindowHours(1000))
        assertEquals(6, RangeHistoryPaging.initialWindowHours(10000))
    }

    @Test fun progressivelyExtendsRealTickHistoryUpToOneWeek() {
        val end = 100L * day
        var window = RangeHistoryPaging.Window(end, 1)
        window = RangeHistoryPaging.older(window.end, window.hours)
        assertEquals(6, window.hours)
        repeat(9) { window = RangeHistoryPaging.older(window.end, window.hours) }
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

    @Test fun automaticallyPrefetchesEnoughRealBarsWithoutChangingReplayCursor() {
        assertTrue(RangeHistoryPaging.shouldPrefetchMoreBars(12, 6, false, false))
        assertTrue(RangeHistoryPaging.shouldPrefetchMoreBars(48, 6, false, false))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(160, 6, false, false))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(12, 96, false, false))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(12, 6, true, false))
        // Replay also needs completed Range bars. Backfilling older BID quotes
        // is safe: the requested end stays at the ALREADY REVEALED cutoff.
        assertTrue(RangeHistoryPaging.shouldPrefetchMoreBars(0, 6, false, true))
        assertTrue(RangeHistoryPaging.shouldPrefetchMoreBars(12, 24, false, true))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(40, 6, false, true))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(0, 48, false, true))
        assertFalse(RangeHistoryPaging.shouldPrefetchMoreBars(0, 6, true, true))
        val end = 200L * day
        val older = RangeHistoryPaging.older(end, 6,
            RangeHistoryPaging.REPLAY_AUTO_MAX_HOURS)
        assertEquals(end, older.end)
        assertEquals(12, older.hours)
    }

    @Test fun replayThousandTickRangeNeedsOlderRealQuotesToFormFirstClosedCandle() {
        val hour = RangeHistoryPaging.HOUR_MILLIS
        val cutoff = 12L * hour
        val quotes = listOf(
            RangePriceTick(3L * hour, 4029.00),
            RangePriceTick(7L * hour, 4040.00),
            RangePriceTick(10L * hour, 4042.00)
        )
        fun replayBars(hours: Int) = RangeBarsEngine.build("XAUUSD",
            quotes.filter { it.timestamp in (cutoff - hours * hour)..cutoff },
            tickSize = 0.01, sizeInPriceTicks = 1_000,
            source = "ctrader:demo:test", includeIncomplete = false)

        // Before this fix, Replay froze at this EMPTY six-hour result forever:
        // auto-extension was explicitly disabled whenever inReplay=true.
        assertTrue(replayBars(6).isEmpty())
        assertTrue(RangeHistoryPaging.shouldPrefetchMoreBars(0, 6, false, true))
        val extended = replayBars(12)
        assertEquals(1, extended.size)
        assertTrue(extended.all { it.closeTime <= cutoff })
    }

    @Test fun denseBrokerWindowsShrinkAndThenSlideWithoutSkippingHours() {
        val end = 100L * day
        val denseCap = RangeHistoryPaging.smallerDenseWindow(24)
        assertEquals(12, denseCap)
        val first = RangeHistoryPaging.older(end, denseCap, denseCap)
        assertEquals(end - 6L * RangeHistoryPaging.HOUR_MILLIS, first.end)
        assertEquals(denseCap, first.hours)
        val smallCap = RangeHistoryPaging.smallerDenseWindow(3)
        assertEquals(1, smallCap)
        val next = RangeHistoryPaging.older(end, 1, smallCap)
        assertEquals(end - RangeHistoryPaging.HOUR_MILLIS, next.end)
    }

    @Test fun fastManualBackfillStillRespectsSmallBrokerDensityCap() {
        val end = 100L * day
        var window = RangeHistoryPaging.Window(end, 1)
        window = RangeHistoryPaging.older(window.end, window.hours, 3)
        assertEquals(3, window.hours)
        val slid = RangeHistoryPaging.older(window.end, window.hours, 3)
        assertEquals(3, slid.hours)
        assertEquals(end - 3L * RangeHistoryPaging.HOUR_MILLIS, slid.end)
    }

    @Test fun historicalJumpCanMoveMonthsBackWithoutRequestingOverOneWeek() {
        val end = 400L * day
        val jump = RangeHistoryPaging.jumpBack(end, 48, 365)
        assertEquals(end - 365L * day, jump.end)
        assertEquals(48, jump.hours)
        assertEquals(48L * RangeHistoryPaging.HOUR_MILLIS, jump.end - jump.start)
    }
}
