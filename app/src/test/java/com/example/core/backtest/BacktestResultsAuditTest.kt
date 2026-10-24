package com.example.core.backtest

import com.example.core.model.ExitReason
import com.example.core.model.PositionSide
import com.example.core.model.TradeJournalEntry
import com.example.core.statistics.StatisticsCalculator
import org.junit.Assert.*
import org.junit.Test

class BacktestResultsAuditTest {
    private fun trade(gross: Double, fee: Double = 0.0) = TradeJournalEntry(
        accountId = 1, symbol = "XAUUSD", side = PositionSide.BUY,
        volume = 0.01, entryPrice = 2000.0, exitPrice = 2001.0,
        profitLoss = gross, commission = fee, openTime = 1000,
        closeTime = 2000, exitReason = ExitReason.MANUAL_CLOSE,
        mode = "BACKTEST"
    )

    @Test fun acceptsRealCalculatorOutputWithCosts() {
        val trades = listOf(trade(12.0, 2.0), trade(-3.0, 1.0))
        val metrics = StatisticsCalculator.calculate(100.0, trades, 106.0)
        BacktestResultsAudit.validate(100.0, 106.0, trades, metrics)
    }

    @Test fun acceptsNoTradeRun() {
        val metrics = StatisticsCalculator.calculate(100.0, emptyList(), 100.0)
        BacktestResultsAudit.validate(100.0, 100.0, emptyList(), metrics)
    }

    @Test fun detectsIncorrectFinalBalance() {
        val trades = listOf(trade(10.0))
        val metrics = StatisticsCalculator.calculate(100.0, trades, 110.0)
        rejects { BacktestResultsAudit.validate(100.0, 111.0, trades, metrics) }
    }

    @Test fun detectsIncorrectTradeCounts() {
        val trades = listOf(trade(10.0))
        val metrics = StatisticsCalculator.calculate(100.0, trades, 110.0)
        rejects { BacktestResultsAudit.validate(100.0, 110.0, trades, metrics.copy(totalTrades = 2)) }
        rejects { BacktestResultsAudit.validate(100.0, 110.0, trades, metrics.copy(winningTrades = 0)) }
    }

    @Test fun detectsTamperedGrossAndNetProfit() {
        val trades = listOf(trade(10.0))
        val metrics = StatisticsCalculator.calculate(100.0, trades, 110.0)
        rejects { BacktestResultsAudit.validate(100.0, 110.0, trades, metrics.copy(grossProfit = 12.0)) }
        rejects { BacktestResultsAudit.validate(100.0, 110.0, trades, metrics.copy(netProfit = 12.0)) }
    }

    @Test fun rejectsNonFiniteReport() {
        val metrics = StatisticsCalculator.calculate(100.0, emptyList(), 100.0)
        rejects { BacktestResultsAudit.validate(100.0, 100.0, emptyList(), metrics.copy(equity = Double.NaN)) }
    }

    private fun rejects(block: () -> Unit) {
        try { block(); fail("Expected inconsistent report to be rejected") }
        catch (_: IllegalArgumentException) {}
    }
}
