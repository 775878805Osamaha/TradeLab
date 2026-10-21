package com.example.core.backtest

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Accounting invariant: mark-to-market equity includes the cost liabilities
 * of positions that have not yet been closed.
 */
class BacktestEquityAccountingTest {
    @Test fun openPositionCostsReduceEquity() {
        val balance = 1000.0
        val grossFloatingProfit = 125.0
        val entryCommission = 7.5
        val accruedSwap = 2.5
        val equity = BacktestEquityAccounting.equity(
            balance, listOf(
                BacktestEquityAccounting.OpenPositionValue(
                    grossFloatingProfit, entryCommission, accruedSwap
                )
            )
        )
        assertEquals(1115.0, equity, 1e-9)
    }

    @Test fun multiplePositionsAndNegativeFloatingProfit() {
        val equity = BacktestEquityAccounting.equity(
            500.0, listOf(
                BacktestEquityAccounting.OpenPositionValue(-20.0, 1.0, 0.0),
                BacktestEquityAccounting.OpenPositionValue(15.0, 2.0, 1.0)
            )
        )
        assertEquals(491.0, equity, 1e-9)
    }

    @Test fun emptyPortfolioEqualsBalance() {
        assertEquals(300.0, BacktestEquityAccounting.equity(300.0, emptyList()), 1e-9)
    }
}
