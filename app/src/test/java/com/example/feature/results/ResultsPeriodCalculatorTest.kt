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
}
