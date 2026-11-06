package com.example.core.market

/**
 * Binance candle-open boundaries in UTC. Weekly candles open Monday 00:00 UTC.
 * A historical request must not include the opening timestamp of the live candle.
 */
object HistoricalCandleBoundary {
    /**
     * Upper bound for a *fully completed* historical bar's opening timestamp.
     * Binance uses exchange UTC grids. cTrader's timestamp is the first tick
     * of a broker bar and may not match an epoch-aligned H4/D1/W1 boundary.
     * For cTrader use a conservative, minute-aligned now-minus-duration bound:
     * do not expose a still-forming candle or manufacture a UTC opening time.
     */
    fun latestClosedRequestTo(nowMillis: Long, intervalMillis: Long, brokerTimed: Boolean): Long {
        require(nowMillis >= intervalMillis && intervalMillis > 0L) { "No completed candle in range" }
        if (!brokerTimed) return currentOpen(nowMillis, intervalMillis) - intervalMillis
        val completedBefore = nowMillis - intervalMillis
        return completedBefore - Math.floorMod(completedBefore, 60_000L)
    }

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
