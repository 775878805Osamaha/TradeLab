package com.example.feature.results

import com.example.core.model.ExitReason
import com.example.core.model.PositionSide
import com.example.core.model.TradeJournalEntry
import org.junit.Assert.*
import org.junit.Test
import java.util.Calendar

class ResultsPeriodCalculatorTest {
    private fun trade(time: Long, profit: Double) = TradeJournalEntry(
        accountId = 1, symbol = "XAUUSD", side = PositionSide.BUY,
        volume = 0.01, entryPrice = 2000.0, exitPrice = 2001.0,
        profitLoss = profit, openTime = time - 1000, closeTime = time,
        exitReason = ExitReason.MANUAL_CLOSE, mode = "BACKTEST"
    )

    private fun date(year: Int, month: Int, day: Int): Long =
        Calendar.getInstance().apply {
            clear()
            set(year, month, day, 12, 0, 0)
        }.timeInMillis

    @Test fun emptyPeriodRetainsRealOpeningBalance() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val result = ResultsPeriodCalculator.calculate(100.0, emptyList(), ResultsPeriod.MONTH, now)
        assertEquals(100.0, result.openingBalance, 0.00001)
        assertEquals(100.0, result.closingBalance, 0.00001)
        assertEquals(0, result.metrics.totalTrades)
    }

    @Test fun monthExcludesEarlierTradesButCarriesTheirBalance() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val trades = listOf(
            trade(date(2026, Calendar.SEPTEMBER, 18), 20.0),
            trade(date(2026, Calendar.OCTOBER, 4), -5.0),
            trade(date(2026, Calendar.OCTOBER, 20), 8.0)
        )
        val result = ResultsPeriodCalculator.calculate(100.0, trades, ResultsPeriod.MONTH, now)
        assertEquals(120.0, result.openingBalance, 0.00001)
        assertEquals(123.0, result.closingBalance, 0.00001)
        assertEquals(2, result.metrics.totalTrades)
        assertEquals(3.0, result.metrics.netProfit, 0.00001)
    }

    @Test fun allPeriodIncludesEveryCompletedTrade() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val result = ResultsPeriodCalculator.calculate(100.0,
            listOf(trade(now - 100_000, 9.0), trade(now - 200_000, -3.0)), ResultsPeriod.ALL, now)
        assertEquals(2, result.metrics.totalTrades)
        assertEquals(106.0, result.closingBalance, 0.00001)
    }

    @Test fun futureTradesNeverEnterResults() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val result = ResultsPeriodCalculator.calculate(100.0,
            listOf(trade(now + 86_400_000L, 50.0)), ResultsPeriod.ALL, now)
        assertEquals(0, result.metrics.totalTrades)
        assertEquals(100.0, result.closingBalance, 0.00001)
    }

    @Test fun weekAndMonthHaveDifferentStartBoundaries() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val week = ResultsPeriodCalculator.cutoff(ResultsPeriod.WEEK, now)!!
        val month = ResultsPeriodCalculator.cutoff(ResultsPeriod.MONTH, now)!!
        assertTrue(week >= month)
        assertTrue(week <= now)
    }

    @Test fun rejectsInvalidOpeningBalance() {
        try {
            ResultsPeriodCalculator.calculate(Double.NaN, emptyList(), ResultsPeriod.ALL, 1000)
            fail("Expected invalid balance rejection")
        } catch (_: IllegalArgumentException) {}
    }
    @Test fun losingPeriodUsesNegativeProfitAndRealBalance() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val result = ResultsPeriodCalculator.calculate(500.0,
            listOf(trade(date(2026, Calendar.OCTOBER, 20), -45.0)), ResultsPeriod.MONTH, now)
        assertEquals(-45.0, result.metrics.netProfit, 0.00001)
        assertEquals(455.0, result.closingBalance, 0.00001)
        assertEquals(1, result.metrics.losingTrades)
    }

    @Test fun sameTradesProduceDifferentMonthAndAllResults() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val trades = listOf(
            trade(date(2026, Calendar.SEPTEMBER, 10), 100.0),
            trade(date(2026, Calendar.OCTOBER, 20), 5.0)
        )
        val month = ResultsPeriodCalculator.calculate(1000.0, trades, ResultsPeriod.MONTH, now)
        val all = ResultsPeriodCalculator.calculate(1000.0, trades, ResultsPeriod.ALL, now)
        assertEquals(5.0, month.metrics.netProfit, 0.00001)
        assertEquals(105.0, all.metrics.netProfit, 0.00001)
        assertEquals(1105.0, month.closingBalance, 0.00001)
        assertEquals(all.closingBalance, month.closingBalance, 0.00001)
        assertTrue(all.curve.size > month.curve.size)
    }

    @Test fun futureDatedTradesCannotInflateOpeningBalance() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val result = ResultsPeriodCalculator.calculate(
            100.0,
            listOf(
                trade(date(2026, Calendar.SEPTEMBER, 2), 15.0),
                trade(now + 86_400_000L, 900.0)
            ),
            ResultsPeriod.MONTH,
            now
        )
        assertEquals(115.0, result.openingBalance, 0.00001)
        assertEquals(115.0, result.closingBalance, 0.00001)
        assertEquals(0, result.metrics.totalTrades)
    }

    @Test fun invalidTradeProfitIsRejectedBeforeRendering() {
        val now = date(2026, Calendar.OCTOBER, 24)
        try {
            ResultsPeriodCalculator.calculate(100.0,
                listOf(trade(now - 1000, Double.NaN)), ResultsPeriod.ALL, now)
            fail("Expected rejection")
        } catch (_: IllegalArgumentException) {}
    }

    @Test fun invalidTradeDurationIsRejected() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val invalid = trade(now - 1000, 10.0).copy(openTime = now)
        try {
            ResultsPeriodCalculator.calculate(100.0, listOf(invalid), ResultsPeriod.ALL, now)
            fail("Expected rejection")
        } catch (_: IllegalArgumentException) {}
    }

    @Test fun shuffledTradesProduceChronologicalMetrics() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val older = trade(now - 100_000, 30.0)
        val newer = trade(now - 10_000, -20.0)
        val a = ResultsPeriodCalculator.calculate(100.0,
            listOf(newer, older), ResultsPeriod.ALL, now)
        val b = ResultsPeriodCalculator.calculate(100.0,
            listOf(older, newer), ResultsPeriod.ALL, now)
        assertEquals(b.metrics.maxDrawdown, a.metrics.maxDrawdown, 0.00001)
        assertEquals(b.closingBalance, a.closingBalance, 0.00001)
        assertEquals(older.closeTime, a.trades.first().closeTime)
    }

    @Test fun fullAccountDisplayAndExportRetainIntratradeRisk() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val trades = listOf(trade(now - 1000, 10.0))
        val metrics = com.example.core.statistics.StatisticsCalculator.calculate(100.0, trades, 105.0)
            .copy(maxDrawdown = 20.0, maxDrawdownPct = 20.0)
        val curve = listOf(com.example.core.model.EquityPoint(now, 110.0, 105.0, 20.0, 125.0))
        val state = ResultsUiState(initialBalance=100.0,currentBalance=110.0,trades=trades,metrics=metrics,equityPoints=curve)
        val report = ResultsPeriodCalculator.forDisplay(state,now)
        assertEquals(20.0, report.metrics.maxDrawdown, 0.00001)
        assertEquals(105.0, report.metrics.equity, 0.00001)
        assertEquals(110.0, report.closingBalance, 0.00001)
        assertEquals(curve, report.curve)
    }

    @Test fun lossOnlyAccountHasNegativeExpectancy() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val result = ResultsPeriodCalculator.calculate(100.0,
            listOf(trade(now-2000,-10.0),trade(now-1000,-20.0)),ResultsPeriod.ALL,now)
        assertEquals(-15.0, result.metrics.expectancy!!, 0.00001)
        assertEquals(0.0, result.metrics.winRatePct, 0.00001)
    }

    @Test fun breakevenTradesRemainInExpectancyDenominator() {
        val now = date(2026, Calendar.OCTOBER, 24)
        val result = ResultsPeriodCalculator.calculate(100.0,
            listOf(trade(now-2000,10.0),trade(now-1000,0.0)),ResultsPeriod.ALL,now)
        assertEquals(5.0, result.metrics.expectancy!!, 0.00001)
        assertEquals(50.0, result.metrics.winRatePct, 0.00001)
    }

}
