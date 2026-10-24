package com.example.core.backtest

import com.example.core.model.PerformanceMetrics
import com.example.core.model.TradeJournalEntry
import kotlin.math.abs
import kotlin.math.max

/**
 * Prevents publishing an inconsistent backtest report even if a statistics
 * implementation changes independently of the execution/ledger engine.
 */
object BacktestResultsAudit {
    fun validate(
        initialBalance: Double,
        finalBalance: Double,
        trades: List<TradeJournalEntry>,
        metrics: PerformanceMetrics
    ) {
        require(initialBalance.isFinite() && finalBalance.isFinite()) {
            "Non-finite account balances"
        }
        require(metrics.totalTrades == trades.size) { "Reported trade count mismatch" }
        require(metrics.winningTrades == trades.count { it.netProfitLoss > 0.0 }) {
            "Reported winning trade count mismatch"
        }
        require(metrics.losingTrades == trades.count { it.netProfitLoss < 0.0 }) {
            "Reported losing trade count mismatch"
        }
        require(metrics.initialBalance.isFinite() &&
            near(metrics.initialBalance, initialBalance)) {
            "Reported initial balance mismatch"
        }
        require(metrics.finalBalance.isFinite() &&
            near(metrics.finalBalance, finalBalance)) {
            "Reported final balance mismatch"
        }
        require(metrics.netProfit.isFinite() &&
            near(metrics.netProfit, finalBalance - initialBalance)) {
            "Reported net profit mismatch"
        }
        require(metrics.equity.isFinite() &&
            near(metrics.equity, finalBalance)) {
            "Reported terminal equity mismatch"
        }
        require(metrics.grossProfit.isFinite() && metrics.grossLoss.isFinite() &&
            metrics.grossProfit >= 0.0 && metrics.grossLoss >= 0.0) {
            "Invalid reported gross PnL"
        }
        val expectedGrossProfit = trades.filter { it.netProfitLoss > 0.0 }
            .sumOf { it.netProfitLoss }
        val expectedGrossLoss = trades.filter { it.netProfitLoss < 0.0 }
            .sumOf { -it.netProfitLoss }
        require(near(metrics.grossProfit, expectedGrossProfit) &&
            near(metrics.grossLoss, expectedGrossLoss)) {
            "Reported gross profit/loss mismatch"
        }
        require(near(metrics.grossProfit - metrics.grossLoss, metrics.netProfit)) {
            "Reported gross and net profit do not reconcile"
        }
    }

    private fun near(a: Double, b: Double): Boolean =
        a.isFinite() && b.isFinite() &&
            abs(a - b) <= max(1e-6, max(abs(a), abs(b)) * 1e-9)
}
