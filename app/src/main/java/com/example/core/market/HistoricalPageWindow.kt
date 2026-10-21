package com.example.core.market

/**
 * Inclusive Binance kline open-time window, aligned to the exchange candle grid.
 * Weekly candles open on Monday 00:00 UTC.
 */
object HistoricalPageWindow {
    fun end(cursor: Long, to: Long, intervalMillis: Long, pageSize: Int): Long? {
        require(cursor >= 0 && to >= cursor)
        require(intervalMillis > 0 && pageSize in 1..1000)
        val weekMillis = 7L * 24 * 60 * 60 * 1000
        val offset = if (intervalMillis == weekMillis) 4L * 24 * 60 * 60 * 1000 else 0L
        val remainder = Math.floorMod(cursor - offset, intervalMillis)
        val delta = if (remainder == 0L) 0L else intervalMillis - remainder
        if (delta > to - cursor) return null
        val firstOpen = cursor + delta
        val available = (to - firstOpen) / intervalMillis
        val steps = minOf(available, pageSize.toLong() - 1L)
        return firstOpen + steps * intervalMillis
    }
}
