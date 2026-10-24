package com.example.feature.backtest

/**
 * Parse a user-entered backtest parameter without substituting an unrelated
 * default. Every field must be finite; domain constraints belong to BacktestConfig.
 */
internal fun parseBacktestNumber(label: String, input: String): Double {
    val value = input.trim().toDoubleOrNull()
    require(value != null && value.isFinite()) {
        "القيمة المدخلة في «$label» يجب أن تكون رقمًا صالحًا"
    }
    return value
}
