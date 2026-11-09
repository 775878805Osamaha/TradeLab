package com.example.core.market

import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToLong

/** Broker digits describe displayed price precision, not necessarily the traded
 * minimum tick increment. Never silently treat digits as a verified tick size. */
data class RangeSymbolPrecision(val digits: Int, val pipPosition: Int) {
    init {
        require(digits in 0..10 && pipPosition in 0..10)
    }

    fun isConfiguredTickRepresentable(configuredTickSize: Double): Boolean {
        if (!configuredTickSize.isFinite() || configuredTickSize <= 0.0) return false
        val displayUnit = 10.0.pow(-digits)
        val ratio = configuredTickSize / displayUnit
        return ratio >= 1.0 && ratio < Long.MAX_VALUE &&
            abs(ratio - ratio.roundToLong()) < 0.000001
    }
}
