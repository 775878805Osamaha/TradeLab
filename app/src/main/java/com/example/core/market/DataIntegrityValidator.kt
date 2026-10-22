package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Tick

sealed class ValidationResult {
    object Valid : ValidationResult()
    data class Invalid(val reason: String) : ValidationResult()

    val isValid: Boolean get() = this is Valid
}

/**
 * DataIntegrityValidator enforces strict data integrity on all market data:
 * - Candle OHLC sanity (high >= max(open, close), low <= min(open, close), high >= low)
 * - Timestamp sanity (openTime > 0, closeTime > openTime)
 * - No duplicate timestamps
 * - Strict chronological sorting by openTime
 * - Replay lookahead barrier enforcement (no future candles past replay barrier)
 * - Tick sanity (bid > 0, ask >= bid, spread >= 0)
 */
object DataIntegrityValidator {

    /**
     * Validates an individual candle for data integrity.
     */
    fun validateCandle(candle: Candle): ValidationResult {
        if (candle.openTime <= 0) {
            return ValidationResult.Invalid("Candle openTime must be positive: ${candle.openTime}")
        }
        if (candle.closeTime <= candle.openTime) {
            return ValidationResult.Invalid("Candle closeTime (${candle.closeTime}) must be strictly greater than openTime (${candle.openTime})")
        }
        if (listOf(candle.open, candle.high, candle.low, candle.close).any { !it.isFinite() || it <= 0.0 }) {
            return ValidationResult.Invalid("Candle OHLC values must be positive and finite")
        }
        if (!candle.volume.isFinite()) {
            return ValidationResult.Invalid("Candle volume must be finite")
        }
        val maxOC = maxOf(candle.open, candle.close)
        val minOC = minOf(candle.open, candle.close)

        if (candle.high < maxOC) {
            return ValidationResult.Invalid("Candle High (${candle.high}) is lower than max(Open, Close) ($maxOC)")
        }
        if (candle.low > minOC) {
            return ValidationResult.Invalid("Candle Low (${candle.low}) is greater than min(Open, Close) ($minOC)")
        }
        if (candle.high < candle.low) {
            return ValidationResult.Invalid("Candle High (${candle.high}) is less than Low (${candle.low})")
        }
        if (candle.volume < 0.0) {
            return ValidationResult.Invalid("Candle volume cannot be negative: ${candle.volume}")
        }
        if (candle.symbol.isBlank()) {
            return ValidationResult.Invalid("Candle symbol cannot be blank")
        }
        return ValidationResult.Valid
    }

    /**
     * Sanitizes a list of candles:
     * 1. Filters out invalid candles violating OHLC or timestamp invariants
     * 2. Eliminates duplicates based on openTime
     * 3. Sorts strictly by openTime in ascending order
     */
    fun sanitizeCandles(candles: List<Candle>): List<Candle> {
        if (candles.isEmpty()) return emptyList()

        return candles
            .filter { validateCandle(it).isValid }
            .distinctBy { it.openTime }
            .sortedBy { it.openTime }
    }

    /**
     * Strict historical validation for backtesting. Unlike sanitizeCandles,
     * this rejects corrupt, mixed-instrument, duplicated or unordered input
     * instead of silently repairing it and changing the tested sample.
     * Market closures are allowed: gaps are not automatically synthetic bars.
     */
    fun validateHistoricalSeries(candles: List<Candle>): ValidationResult {
        if (candles.isEmpty()) return ValidationResult.Invalid("Historical series is empty")
        val symbol = candles.first().symbol
        val timeframe = candles.first().timeframe
        var previousOpen = Long.MIN_VALUE
        for ((index, candle) in candles.withIndex()) {
            val validity = validateCandle(candle)
            if (validity is ValidationResult.Invalid) {
                return ValidationResult.Invalid("Bar $index: ${validity.reason}")
            }
            if (candle.symbol != symbol || candle.timeframe != timeframe) {
                return ValidationResult.Invalid("Mixed symbol or timeframe at bar $index")
            }
            if (candle.openTime <= previousOpen) {
                return ValidationResult.Invalid("Duplicate or unordered timestamp at bar $index")
            }
            previousOpen = candle.openTime
        }
        return ValidationResult.Valid
    }

    /**
     * Enforces replay temporal barrier.
     * Prevents future candles during historical replay, eliminating lookahead bias.
     */
    fun enforceReplayBarrier(candles: List<Candle>, currentReplayTime: Long): List<Candle> {
        return candles.filter { it.openTime <= currentReplayTime }
    }

    /**
     * Validates a market tick.
     */
    fun validateTick(tick: Tick): ValidationResult {
        if (!tick.bid.isFinite() || !tick.ask.isFinite() ||
            !tick.last.isFinite() || tick.last <= 0.0) {
            return ValidationResult.Invalid("Tick prices must be positive and finite")
        }
        if (tick.bid <= 0.0) {
            return ValidationResult.Invalid("Tick bid must be positive: ${tick.bid}")
        }
        if (tick.ask < tick.bid) {
            return ValidationResult.Invalid("Tick ask (${tick.ask}) cannot be lower than bid (${tick.bid})")
        }
        if (tick.timestamp <= 0L) {
            return ValidationResult.Invalid("Tick timestamp must be positive: ${tick.timestamp}")
        }
        if (tick.symbol.isBlank()) {
            return ValidationResult.Invalid("Tick symbol cannot be blank")
        }
        return ValidationResult.Valid
    }
}
