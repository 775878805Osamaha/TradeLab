package com.example.feature.replay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReplayPerformanceAnalyticsTest {
    @Test
    fun emptySessionHasZeroTradesAndNoProfitFactor() {
        val report = ReplayPerformanceAnalytics.calculate(emptyList(), emptyList(), 1000.0, 1000.0)
        assertEquals(0, report.closedCount)
        assertEquals(0.0, report.maxEquityDrawdownPercent, 0.000001)
        assertEquals(0.0, report.equityReturnPercent, 0.000001)
        assertNull(report.profitFactor)
    }

    @Test
    fun peakToTroughDrawdownIsCalculatedFromHistoricalPeak() {
        val report = ReplayPerformanceAnalytics.calculate(
            trades = emptyList(),
            samples = listOf(
                ReplayEquitySample(0, 1000.0, 1000.0),
                ReplayEquitySample(1, 1200.0, 1200.0),
                ReplayEquitySample(2, 900.0, 900.0),
                ReplayEquitySample(3, 1100.0, 1100.0)
            ),
            initialBalance = 1000.0,
            currentEquity = 1100.0
        )
        assertEquals(1200.0, report.peakEquity, 0.000001)
        assertEquals(300.0, report.maxEquityDrawdownAmount, 0.000001)
        assertEquals(25.0, report.maxEquityDrawdownPercent, 0.000001)
        assertEquals(100.0 / 1200.0 * 100.0, report.currentDrawdownPercent, 0.000001)
        assertEquals(10.0, report.equityReturnPercent, 0.000001)
        assertEquals(4, report.sampledBars)
    }

    @Test
    fun historyIsSortedBeforeAnalyticsAndCsvExport() {
        val samples = listOf(
            ReplayEquitySample(2, 900.0, 920.0),
            ReplayEquitySample(0, 1000.0, 1000.0),
            ReplayEquitySample(1, 1200.0, 1200.0)
        )
        val report = ReplayPerformanceAnalytics.calculate(emptyList(), samples, 1000.0, 900.0)
        assertEquals(25.0, report.maxEquityDrawdownPercent, 0.000001)
        val csv = ReplayPerformanceAnalytics.exportEquityCsv(samples)
        val lines = csv.trim().lines()
        assertEquals("candle_index,balance_usd,equity_usd", lines.first())
        assertEquals("0,1000.000000,1000.000000", lines[1])
        assertEquals("1,1200.000000,1200.000000", lines[2])
        assertEquals("2,920.000000,900.000000", lines[3])
    }

    @Test
    fun summaryExportContainsReproducibleKeyMetrics() {
        val report = ReplayPerformanceAnalytics.calculate(
            emptyList(),
            listOf(ReplayEquitySample(0, 1000.0, 1000.0), ReplayEquitySample(1, 850.0, 850.0)),
            1000.0,
            850.0
        )
        val csv = ReplayPerformanceAnalytics.exportSummaryCsv(report)
        assertEquals("metric,value", csv.lineSequence().first())
        org.junit.Assert.assertTrue(csv.contains("maximum_drawdown_percent,15.000000"))
        org.junit.Assert.assertTrue(csv.contains("equity_return_percent,-15.000000"))
        org.junit.Assert.assertTrue(csv.contains("sampled_bars,2.000000"))
        org.junit.Assert.assertTrue(ReplayPerformanceAnalytics.exportTradesCsv(emptyList()).startsWith("closed_trade_number"))
    }

    @Test
    fun nonFiniteEquitySamplesAreExcludedFromStatisticsAndExport() {
        val samples = listOf(
            ReplayEquitySample(0, 1000.0, 1000.0),
            ReplayEquitySample(1, Double.NaN, Double.NaN),
            ReplayEquitySample(2, 950.0, 950.0)
        )
        val report = ReplayPerformanceAnalytics.calculate(emptyList(), samples, 1000.0, 950.0)
        assertEquals(2, report.sampledBars)
        assertEquals(5.0, report.maxEquityDrawdownPercent, 0.000001)
        assertEquals(3, ReplayPerformanceAnalytics.exportEquityCsv(samples).trim().lines().size)
    }
}
