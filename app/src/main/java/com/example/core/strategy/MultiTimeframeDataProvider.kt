package com.example.core.strategy

import com.example.core.model.Candle
import com.example.core.model.Timeframe

class HtfLookaheadViolation(message: String) : RuntimeException(message)

/**
 * Multi-Timeframe Data Provider with strict no-lookahead protection.
 * 
 * At lower-timeframe execution time T (e.g. M5 candle open/close):
 * Higher-timeframe (HTF) confirmation (e.g. H1, H4, D1) may ONLY access candles
 * that have ALREADY COMPLETED (candle.closeTime <= T).
 * 
 * Partially-formed future HTF candles are strictly excluded to eliminate lookahead bias.
 */
class MultiTimeframeDataProvider(
    val executionTimeframe: Timeframe,
    val higherTimeframe: Timeframe,
    private val allHtfCandles: List<Candle>
) {
    init {
        require(higherTimeframe.minutes >= executionTimeframe.minutes) {
            "Higher timeframe (${higherTimeframe.displayName}) must be >= execution timeframe (${executionTimeframe.displayName})"
        }
    }

    /**
     * Returns ONLY completed HTF candles available strictly at or before [currentExecutionTimestamp].
     * An HTF candle is considered closed only if candle.closeTime <= currentExecutionTimestamp.
     */
    fun getCompletedHtfCandles(currentExecutionTimestamp: Long): List<Candle> {
        val completed = allHtfCandles.filter { it.closeTime <= currentExecutionTimestamp }
        // Verify chronological order
        return completed.sortedBy { it.openTime }
    }

    /**
     * Returns the latest fully closed HTF candle relative to [currentExecutionTimestamp].
     */
    fun getLatestClosedHtfCandle(currentExecutionTimestamp: Long): Candle? {
        val completed = getCompletedHtfCandles(currentExecutionTimestamp)
        return completed.lastOrNull()
    }

    /**
     * Validates that a requested candle does not violate the HTF boundary.
     * Throws [HtfLookaheadViolation] if the candle closed after [currentExecutionTimestamp].
     */
    fun enforceNoLookahead(candle: Candle, currentExecutionTimestamp: Long) {
        if (candle.closeTime > currentExecutionTimestamp) {
            throw HtfLookaheadViolation(
                "Access Denied: HTF candle ${candle.symbol} (${candle.timeframe.displayName}) closing at ${candle.closeTime} is in the future relative to execution time $currentExecutionTimestamp."
            )
        }
    }
}
