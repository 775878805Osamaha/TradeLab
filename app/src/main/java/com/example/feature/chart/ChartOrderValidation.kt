package com.example.feature.chart

import com.example.core.model.OrderSide

/**
 * Fail-closed validation for chart paper orders. SL/TP are optional but must
 * be on the correct side of the executable bid/ask when supplied.
 */
object ChartOrderValidation {
    fun isValid(side: OrderSide, volume: Double, entry: Double, sl: Double?, tp: Double?): Boolean {
        if (!volume.isFinite() || volume <= 0.0 || !entry.isFinite() || entry <= 0.0) return false
        if (sl != null && (!sl.isFinite() || sl <= 0.0)) return false
        if (tp != null && (!tp.isFinite() || tp <= 0.0)) return false
        return when (side) {
            OrderSide.BUY -> (sl == null || sl < entry) && (tp == null || tp > entry)
            OrderSide.SELL -> (sl == null || sl > entry) && (tp == null || tp < entry)
            else -> false
        }
    }

    fun isValidLot(volume: Double, minLot: Double, maxLot: Double, lotStep: Double): Boolean {
        if (!volume.isFinite() || !minLot.isFinite() || !maxLot.isFinite() ||
            !lotStep.isFinite() || minLot <= 0.0 || maxLot < minLot || lotStep <= 0.0 ||
            volume < minLot - 1e-9 || volume > maxLot + 1e-9) return false
        val steps = (volume - minLot) / lotStep
        return steps.isFinite() && kotlin.math.abs(steps - kotlin.math.round(steps)) < 1e-6
    }

    /** Estimated stop loss in quote-currency units; excludes spread, slippage and fees. */
    fun estimatedLoss(volume: Double, entry: Double, sl: Double?, contractSize: Double): Double? {
        if (sl == null || !volume.isFinite() || volume <= 0.0 ||
            !entry.isFinite() || !sl.isFinite() ||
            !contractSize.isFinite() || contractSize <= 0.0) return null
        val result = kotlin.math.abs(entry - sl) * volume * contractSize
        return result.takeIf { it.isFinite() }
    }
}
