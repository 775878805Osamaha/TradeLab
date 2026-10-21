package com.example.core.backtest

/** Pure accounting helper shared by the simulator and regression tests. */
internal object BacktestEquityAccounting {
    data class OpenPositionValue(
        val grossProfitLoss: Double,
        val entryCommission: Double,
        val accruedSwap: Double
    )

    fun equity(balance: Double, positions: List<OpenPositionValue>): Double =
        balance + positions.sumOf {
            it.grossProfitLoss - it.entryCommission - it.accruedSwap
        }
}
