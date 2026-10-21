package com.example.core.backtest

/**
 * A requested fixed lot must not be silently increased to the broker minimum.
 * Such an increase changes the user's intended risk.
 */
internal object BacktestLotSizing {
    fun fixedLot(requested: Double, minLot: Double, maxLot: Double): Double? {
        if (!requested.isFinite() || !minLot.isFinite() || !maxLot.isFinite() ||
            requested <= 0.0 || minLot <= 0.0 || maxLot < minLot ||
            requested < minLot || requested > maxLot) return null
        return requested
    }
}
