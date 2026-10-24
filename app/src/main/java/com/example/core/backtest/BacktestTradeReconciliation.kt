package com.example.core.backtest

import com.example.core.model.TradeJournalEntry
import kotlin.math.abs
import kotlin.math.max

/**
 * Cash accounting invariant for historical simulation. Independent of the
 * statistics layer so a broken report cannot silently mask a broken ledger.
 */
object BacktestTradeReconciliation {
    fun validate(initialBalance: Double, finalBalance: Double, trades: List<TradeJournalEntry>) {
        require(initialBalance.isFinite() && initialBalance > 0.0) { "Invalid initial balance" }
        require(finalBalance.isFinite()) { "Invalid final balance" }

        // Compensated sum reduces numerical drift across long backtests.
        var sum = 0.0
        var correction = 0.0
        trades.forEachIndexed { index, trade ->
            require(trade.volume.isFinite() && trade.volume > 0.0) {
                "Invalid trade volume at index $index"
            }
            require(trade.entryPrice.isFinite() && trade.entryPrice > 0.0 &&
                trade.exitPrice.isFinite() && trade.exitPrice > 0.0) {
                "Invalid trade price at index $index"
            }
            require(trade.closeTime >= trade.openTime) {
                "Trade closes before opening at index $index"
            }
            require(trade.profitLoss.isFinite() && trade.commission.isFinite() &&
                trade.commission >= 0.0 && trade.swap.isFinite() &&
                trade.netProfitLoss.isFinite()) {
                "Invalid trade cash flow at index $index"
            }
            val expectedNet = trade.profitLoss - trade.commission - trade.swap
            require(expectedNet.isFinite() &&
                abs(expectedNet - trade.netProfitLoss) <= tolerance(expectedNet)) {
                "Trade costs do not reconcile at index $index"
            }
            val adjusted = trade.netProfitLoss - correction
            val next = sum + adjusted
            correction = (next - sum) - adjusted
            sum = next
        }
        val expectedBalance = initialBalance + sum
        require(expectedBalance.isFinite() &&
            abs(expectedBalance - finalBalance) <= tolerance(expectedBalance)) {
            "Closed trades do not reconcile with final backtest balance"
        }
    }

    private fun tolerance(value: Double) = max(1e-6, abs(value) * 1e-9)
}
