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
        // Compute the remainder without subtracting the weekly offset from
        // the epoch (which would overflow for extreme timestamps).
        val remainder = Math.floorMod(nowMillis, intervalMillis)
        val target = Math.floorMod(offset, intervalMillis)
        val elapsed = Math.floorMod(remainder - target, intervalMillis)
        return nowMillis - elapsed
    }

    fun isClosedRange(to: Long, nowMillis: Long, intervalMillis: Long): Boolean =
        to < currentOpen(nowMillis, intervalMillis)
}
