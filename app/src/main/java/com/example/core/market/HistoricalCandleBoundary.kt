package com.example.core.market

/**
 * Binance candle-open boundaries in UTC. Weekly candles open Monday 00:00 UTC.
 * A historical request must not include the opening timestamp of the live candle.
 */
object HistoricalCandleBoundary {
    fun currentOpen(nowMillis: Long, intervalMillis: Long): Long {
        require(nowMillis >= 0 && intervalMillis > 0) { "Invalid candle boundary" }
        val weekMillis = 7L * 24 * 60 * 60 * 1000
        val offset = if (intervalMillis == weekMillis) 4L * 24 * 60 * 60 * 1000 else 0L
        val shifted = nowMillis - offset
        return Math.floorDiv(shifted, intervalMillis) * intervalMillis + offset
    }

    fun isClosedRange(to: Long, nowMillis: Long, intervalMillis: Long): Boolean =
        to < currentOpen(nowMillis, intervalMillis)
}
