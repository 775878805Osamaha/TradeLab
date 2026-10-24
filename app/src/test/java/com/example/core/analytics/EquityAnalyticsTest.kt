package com.example.core.analytics

import org.junit.Assert.*
import org.junit.Test

class EquityAnalyticsTest {
    private fun points(vararg equity: Double): List<EquityAnalytics.Point> =
        equity.mapIndexed { index, value -> EquityAnalytics.Point(index * 60_000L, value) }

    @Test fun emptyCurveHasNoSummary() {
        assertNull(EquityAnalytics.summarize(emptyList()))
    }

    @Test fun oneObservationHasNoReturnsOrDrawdown() {
        val s = EquityAnalytics.summarize(points(1000.0))!!
        assertEquals(0.0, s.returnPercent, 0.0)
        assertEquals(0.0, s.maxDrawdown.percent, 0.0)
        assertEquals(0, s.positivePeriods)
        assertNull(s.recoveryFactor)
    }

    @Test fun drawdownTracksPeakToTroughNotInitialCapital() {
        val s = EquityAnalytics.summarize(points(100.0, 120.0, 90.0, 110.0))!!
        assertEquals(1, s.maxDrawdown.peakIndex)
        assertEquals(2, s.maxDrawdown.troughIndex)
        assertEquals(30.0, s.maxDrawdown.amount, 0.00001)
        assertEquals(25.0, s.maxDrawdown.percent, 0.00001)
        assertEquals(10.0, s.netProfit, 0.00001)
        assertEquals(10.0 / 30.0, s.recoveryFactor!!, 0.00001)
    }

    @Test fun returnsAreComputedFromPriorObservation() {
        val s = EquityAnalytics.summarize(points(100.0, 110.0, 99.0))!!
        assertEquals(-1.0, s.returnPercent, 0.00001)
        assertEquals(0.0, s.meanPeriodReturnPercent, 0.00001)
        assertEquals(10.0, s.periodReturnStdDevPercent, 0.00001)
        assertEquals(50.0, s.periodWinRatePercent, 0.00001)
    }

    @Test fun streaksResetOnFlatPeriods() {
        val s = EquityAnalytics.summarize(points(100.0, 110.0, 120.0, 120.0, 110.0, 100.0))!!
        assertEquals(2, s.longestWinningStreak)
        assertEquals(2, s.longestLosingStreak)
        assertEquals(1, s.flatPeriods)
    }

    @Test fun allProfitablePeriodsHaveNoRecoveryFactor() {
        val s = EquityAnalytics.summarize(points(100.0, 110.0, 120.0))!!
        assertEquals(100.0, s.periodWinRatePercent, 0.0)
        assertNull(s.recoveryFactor)
    }

    @Test fun rejectsUnorderedAndDuplicateTimes() {
        try {
            EquityAnalytics.summarize(listOf(EquityAnalytics.Point(10L, 100.0), EquityAnalytics.Point(10L, 110.0)))
            fail("Expected duplicate time rejection")
        } catch (_: IllegalArgumentException) {}
    }

    @Test fun rejectsInvalidEquity() {
        for (value in listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            try {
                EquityAnalytics.summarize(points(100.0, value))
                fail("Expected invalid equity rejection")
            } catch (_: IllegalArgumentException) {}
        }
    }

    @Test fun negativeNetProfitHasNegativeRecoveryFactor() {
        val s = EquityAnalytics.summarize(points(100.0, 80.0))!!
        assertEquals(-1.0, s.recoveryFactor!!, 0.00001)
    }
}
