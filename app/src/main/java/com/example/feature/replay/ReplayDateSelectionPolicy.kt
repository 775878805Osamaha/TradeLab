package com.example.feature.replay

/** Date picker timestamps are UTC midnight epoch millis. Never seek into the future. */
object ReplayDateSelectionPolicy {
    fun isValid(timestampMillis: Long, nowMillis: Long): Boolean =
        timestampMillis >= 0L && nowMillis >= 0L && timestampMillis <= nowMillis

    fun shouldShowNoData(isLoading: Boolean, candleCount: Int): Boolean =
        !isLoading && candleCount <= 0
}
