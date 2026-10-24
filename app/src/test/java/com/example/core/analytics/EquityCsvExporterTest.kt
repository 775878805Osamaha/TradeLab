package com.example.core.analytics

import org.junit.Assert.*
import org.junit.Test

class EquityCsvExporterTest {
    private fun p(t: Long, e: Double) = EquityAnalytics.Point(t, e)

    @Test fun emptyCurveExportsHeaderOnly() {
        assertEquals(1, EquityCsvExporter.export(emptyList()).trim().lines().size)
    }

    @Test fun exportedRowsHaveFixedColumnsAndNoInventedBars() {
        val csv = EquityCsvExporter.export(listOf(p(1000, 100.0), p(5000, 110.0), p(9000, 99.0)))
        val lines = csv.trim().lines()
        assertEquals(4, lines.size)
        assertTrue(lines.all { it.split(',').size == 6 })
        assertEquals("1000", lines[1].split(',')[0])
        assertEquals("5000", lines[2].split(',')[0])
        assertEquals("9000", lines[3].split(',')[0])
    }

    @Test fun drawdownIsComputedFromPeak() {
        val lines = EquityCsvExporter.export(listOf(p(1000, 100.0), p(2000, 120.0), p(3000, 90.0))).trim().lines()
        assertEquals("30.00000000", lines[3].split(',')[4])
        assertEquals("25.00000000", lines[3].split(',')[5])
    }

    @Test fun rejectsDuplicateTimestamps() {
        try {
            EquityCsvExporter.export(listOf(p(1000, 100.0), p(1000, 101.0)))
            fail("Expected validation")
        } catch (_: IllegalArgumentException) {}
    }

    @Test fun rejectsNonFiniteEquity() {
        try {
            EquityCsvExporter.export(listOf(p(1000, Double.NaN)))
            fail("Expected validation")
        } catch (_: IllegalArgumentException) {}
    }

    @Test fun summaryContainsKeyMetrics() {
        val summary = EquityAnalytics.summarize(listOf(p(1000, 100.0), p(2000, 80.0)))!!
        val csv = EquityCsvExporter.exportSummary(summary)
        assertTrue(csv.contains("max_drawdown_percent,20.0"))
        assertTrue(csv.contains("net_profit,-20.0"))
        assertTrue(csv.contains("longest_losing_streak,1"))
    }
}
