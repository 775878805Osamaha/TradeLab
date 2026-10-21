package com.example.core.backtest

import kotlin.math.abs

/**
 * Calculate risk from the executable entry quote, never from the mid candle
 * close. A stop on the wrong side of the entry cannot define valid risk.
 */
internal object BacktestRiskDistance {
    fun pips(isBuy: Boolean, bid: Double, ask: Double, stopLoss: Double?, pipSize: Double): Double? {
        if (!bid.isFinite() || !ask.isFinite() || (stopLoss != null && !stopLoss.isFinite()) ||
            !pipSize.isFinite() || bid <= 0.0 || ask < bid ||
            (stopLoss != null && stopLoss <= 0.0) || pipSize <= 0.0) return null
        if (stopLoss == null) return 25.0 // Legacy default after quote validation.
        val entry = if (isBuy) ask else bid
        if (isBuy && stopLoss >= entry || !isBuy && stopLoss <= entry) return null
        val distance = abs(entry - stopLoss) / pipSize
        return distance.takeIf { it.isFinite() && it > 0.0 }
    }
}
