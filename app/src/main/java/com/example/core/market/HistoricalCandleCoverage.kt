package com.example.core.market

import com.example.core.model.Candle

/**
 * Binance spot trades continuously. Missing bars must trigger a refetch,
 * not silently be interpreted as a complete cached history.
 */
object HistoricalCandleCoverage {
    fun isComplete(
        candles: List<Candle>,
        from: Long,
        to: Long,
        intervalMillis: Long
    ): Boolean {
        if (from < 0L || to < from || intervalMillis <= 0L || candles.isEmpty()) return false
        // Binance weekly klines open on Monday 00:00 UTC, not at the Unix
        // epoch (Thursday). All other supported intervals are epoch-aligned.
        val week = 7L * 24 * 60 * 60 * 1000
        val mondayOffset = 4L * 24 * 60 * 60 * 1000
        val offset = if (intervalMillis == week) mondayOffset else 0L
        val shifted = from - offset
        val remainder = Math.floorMod(shifted, intervalMillis)
        val first = if (remainder == 0L) from else from + (intervalMillis - remainder)
        if (first > to) return false
        val expectedCount = (to - first) / intervalMillis + 1L
        if (candles.size.toLong() != expectedCount) return false
        var expected = first
        for ((index, candle) in candles.withIndex()) {
            if (candle.openTime != expected) return false
            if (candle.closeTime <= candle.openTime) return false
            if (index < candles.lastIndex) {
                if (expected > Long.MAX_VALUE - intervalMillis) return false
                expected += intervalMillis
            }
        }
        return true
    }
}
