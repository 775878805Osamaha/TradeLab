package com.example.core.backtest

import com.example.core.model.EquityPoint
import kotlin.math.abs
import kotlin.math.max

/** Validates the actual equity curve before publishing a completed backtest. */
object BacktestEquityIntegrity {
    fun validate(points: List<EquityPoint>, initialBalance: Double, finalBalance: Double) {
        require(initialBalance.isFinite() && initialBalance > 0.0) { "Invalid initial balance" }
        require(finalBalance.isFinite()) { "Invalid final balance" }
        if (points.isEmpty()) {
            require(abs(finalBalance - initialBalance) <= tolerance(initialBalance)) {
                "Empty equity curve cannot hide a balance change"
            }
            return
        }
        var previousTimestamp = -1L
        var previousHigh = initialBalance
        points.forEachIndexed { index, point ->
            require(point.timestamp >= 0L && point.timestamp > previousTimestamp) {
                "Equity timestamps must be strictly increasing at index $index"
            }
            require(point.balance.isFinite() && point.equity.isFinite() &&
                point.drawdown.isFinite() && point.highWatermark.isFinite()) {
                "Non-finite equity observation at index $index"
            }
            require(point.highWatermark + tolerance(point.highWatermark) >= previousHigh &&
                point.highWatermark + tolerance(point.highWatermark) >= point.equity) {
                "Invalid equity high-water mark at index $index"
            }
            require(abs(point.drawdown - (point.highWatermark - point.equity)) <=
                tolerance(point.highWatermark)) {
                "Drawdown does not reconcile at index $index"
            }
            previousTimestamp = point.timestamp
            previousHigh = point.highWatermark
        }
        require(abs(points.first().balance - initialBalance) <= tolerance(initialBalance)) {
            "Initial equity snapshot does not match account balance"
        }
        require(abs(points.last().balance - finalBalance) <= tolerance(finalBalance)) {
            "Final equity snapshot does not match account balance"
        }
        require(abs(points.last().equity - finalBalance) <= tolerance(finalBalance)) {
            "Final equity must reflect closed positions"
        }
    }

    private fun tolerance(value: Double): Double = max(1e-7, abs(value) * 1e-9)
}
