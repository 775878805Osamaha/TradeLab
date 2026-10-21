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
        // The exchange's bar opens are interval-aligned for intraday/daily candles.
        // Weekly Binance candles are Monday-aligned; the caller should refetch
        // rather than assume a full hit based on Unix epoch alignment.
        if (intervalMillis >= 7L * 24 * 60 * 60 * 1000) return false
        val first = (from / intervalMillis) * intervalMillis +
            if (from % intervalMillis == 0L) 0L else intervalMillis
        if (first > to) return false
        val expectedCount = (to - first) / intervalMillis + 1L
        if (candles.size.toLong() != expectedCount) return false
        var expected = first
        for (candle in candles) {
            if (candle.openTime != expected) return false
            if (candle.closeTime <= candle.openTime) return false
            if (expected != candles.last().openTime) {
                if (expected > Long.MAX_VALUE - intervalMillis) return false
                expected += intervalMillis
            }
        }
        return true
    }
}
