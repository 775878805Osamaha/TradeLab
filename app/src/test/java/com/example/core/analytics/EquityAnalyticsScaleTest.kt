package com.example.core.analytics

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.sqrt

class EquityAnalyticsScaleTest {
    @Test fun largeFlatCurveHasZeroVarianceAndNoDrawdown() {
        val points = (0 until 100_000).map { EquityAnalytics.Point(it.toLong(), 1000.0) }
        val summary = EquityAnalytics.summarize(points)!!
        assertEquals(100_000, summary.observations)
        assertEquals(99_999, summary.flatPeriods)
        assertEquals(0.0, summary.periodReturnStdDevPercent, 0.0)
        assertEquals(0.0, summary.maxDrawdown.percent, 0.0)
    }

    @Test fun welfordMatchesReferencePopulationVariance() {
        val points = listOf(100.0, 110.0, 99.0, 108.9).mapIndexed { i, e ->
            EquityAnalytics.Point(i.toLong(), e)
        }
        val summary = EquityAnalytics.summarize(points)!!
        val returns = listOf(10.0, -10.0, 10.0)
        val mean = returns.average()
        val variance = returns.sumOf { (it - mean) * (it - mean) } / returns.size
        assertEquals(mean, summary.meanPeriodReturnPercent, 1e-10)
        assertEquals(sqrt(variance), summary.periodReturnStdDevPercent, 1e-10)
    }

    @Test fun largeDeclineUsesTruePeakAndTrough() {
        val points = (0 until 50_000).map { i ->
            EquityAnalytics.Point(i.toLong(), if (i < 25_000) 100.0 + i else 25_100.0 - (i - 25_000) * 0.5)
        }
        val summary = EquityAnalytics.summarize(points)!!
        assertEquals(24_999, summary.maxDrawdown.peakIndex)
        assertEquals(49_999, summary.maxDrawdown.troughIndex)
        assertTrue(summary.maxDrawdown.amount > 0.0)
    }
}
