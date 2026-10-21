package com.example.ui.components.chart

import java.util.Locale
import kotlin.math.abs

/**
 * A presentation-only fallback when exchange tick-size metadata is unavailable.
 * Preserve sub-cent quotes instead of rounding all assets to two decimals.
 * This does NOT infer contract tick size, pip size or trade execution precision.
 */
internal object QuotePriceFormatter {
    fun decimals(value: Double): Int = when {
        !value.isFinite() -> 2
        abs(value) >= 100.0 -> 2
        abs(value) >= 1.0 -> 4
        else -> 8
    }

    fun price(value: Double): String =
        if (value.isFinite()) String.format(Locale.US, "%.${decimals(value)}f", value) else "—"

    fun spread(value: Double): String =
        if (value.isFinite() && value >= 0.0) {
            val precision = when {
                value == 0.0 -> 2
                value >= 1.0 -> 4
                value >= 0.01 -> 6
                else -> 8
            }
            String.format(Locale.US, "%.${precision}f", value)
        } else "—"
}
