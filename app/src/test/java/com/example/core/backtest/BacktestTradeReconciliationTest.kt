package com.example.core.backtest

import com.example.core.model.ExitReason
import com.example.core.model.PositionSide
import com.example.core.model.TradeJournalEntry
import org.junit.Assert.*
import org.junit.Test

class BacktestTradeReconciliationTest {
    private fun trade(gross: Double, fee: Double = 0.0, swap: Double = 0.0) =
        TradeJournalEntry(
            accountId = 1,
            symbol = "XAUUSD",
            side = PositionSide.BUY,
            volume = 0.01,
            entryPrice = 2000.0,
            exitPrice = 2010.0,
            profitLoss = gross,
            commission = fee,
            swap = swap,
            openTime = 1000,
            closeTime = 2000,
            exitReason = ExitReason.MANUAL_CLOSE
        )

    @Test fun reconcilesProfitsLossesAndExecutionCosts() {
        BacktestTradeReconciliation.validate(
            100.0, 106.0,
            listOf(trade(12.0, 2.0, 1.0), trade(-2.0, 1.0))
        )
    }

    @Test fun noTradesMustPreserveStartingBalance() {
        BacktestTradeReconciliation.validate(100.0, 100.0, emptyList())
        rejects { BacktestTradeReconciliation.validate(100.0, 101.0, emptyList()) }
    }

    @Test fun detectsMissingTradeOrIncorrectFinalBalance() {
        rejects { BacktestTradeReconciliation.validate(100.0, 110.0, listOf(trade(9.0))) }
    }

    @Test fun rejectsTamperedNetProfitAndInvalidCosts() {
        rejects {
            BacktestTradeReconciliation.validate(
                100.0, 110.0,
                listOf(trade(10.0).copy(netProfitLoss = 10.0, commission = 3.0))
            )
        }
        rejects { BacktestTradeReconciliation.validate(100.0, 100.0, listOf(trade(0.0, -1.0))) }
    }

    @Test fun rejectsTradeClosingBeforeOpening() {
        rejects {
            BacktestTradeReconciliation.validate(
                100.0, 101.0,
                listOf(trade(1.0).copy(closeTime = 999))
            )
        }
    }

    @Test fun rejectsNonFiniteTradeValues() {
        rejects { BacktestTradeReconciliation.validate(100.0, 100.0, listOf(trade(Double.NaN))) }
        rejects { BacktestTradeReconciliation.validate(100.0, Double.POSITIVE_INFINITY, emptyList()) }
    }

    private fun rejects(block: () -> Unit) {
        try { block(); fail("Expected reconciliation to reject invalid ledger") }
        catch (_: IllegalArgumentException) {}
    }
}
