package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoricalCandleCoverageTest {
    private fun bar(t: Long) = Candle(
        symbol = "BTCUSDT", timeframe = Timeframe.M1,
        openTime = t, open = 100.0, high = 102.0, low = 99.0, close = 101.0,
        source = "BINANCE_HISTORICAL"
    )

    @Test fun completeWindow() {
        assertTrue(HistoricalCandleCoverage.isComplete(
            listOf(bar(60_000), bar(120_000), bar(180_000)), 60_000, 180_000, 60_000))
    }

    @Test fun missingMiddleCandle() {
        assertFalse(HistoricalCandleCoverage.isComplete(
            listOf(bar(60_000), bar(180_000)), 60_000, 180_000, 60_000))
    }

    @Test fun duplicateCandle() {
        assertFalse(HistoricalCandleCoverage.isComplete(
            listOf(bar(60_000), bar(60_000), bar(180_000)), 60_000, 180_000, 60_000))
    }

    @Test fun unalignedRequestStart() {
        assertTrue(HistoricalCandleCoverage.isComplete(
            listOf(bar(120_000), bar(180_000)), 90_000, 180_000, 60_000))
    }

    @Test fun weeklyCandlesAlignToMonday() {
        val week = 604_800_000L
        val monday = 345_600_000L
        assertTrue(HistoricalCandleCoverage.isComplete(
            listOf(bar(monday), bar(monday + week)),
            monday, monday + week, week))
    }

    @Test fun weeklyMissingBarIsIncomplete() {
        val week = 604_800_000L
        val monday = 345_600_000L
        assertFalse(HistoricalCandleCoverage.isComplete(
            listOf(bar(monday), bar(monday + 2 * week)),
            monday, monday + 2 * week, week))
    }
    @Test fun weeklyWindowStartingBeforeMondayFindsFirstMonday() {
        val week = 604_800_000L
        val monday = 345_600_000L
        assertTrue(HistoricalCandleCoverage.isComplete(
            listOf(bar(monday), bar(monday + week)), 0L, monday + week, week))
    }

    @Test fun windowNearLongMaxValueDoesNotOverflowWhenAligning() {
        val interval = 60_000L
        val aligned = Long.MAX_VALUE - Math.floorMod(Long.MAX_VALUE, interval)
        assertTrue(HistoricalCandleCoverage.isComplete(
            listOf(bar(aligned)), aligned - 1L, aligned, interval))
        assertFalse(HistoricalCandleCoverage.isComplete(
            listOf(bar(aligned)), aligned + 1L, Long.MAX_VALUE, interval))
    }

    @Test fun emptyOrInvalidWindowsAreNeverComplete() {
        assertFalse(HistoricalCandleCoverage.isComplete(emptyList(), 0L, 60_000L, 60_000L))
        assertFalse(HistoricalCandleCoverage.isComplete(listOf(bar(0L)), 60_000L, 0L, 60_000L))
        assertFalse(HistoricalCandleCoverage.isComplete(listOf(bar(0L)), 0L, 60_000L, 0L))
    }

}
