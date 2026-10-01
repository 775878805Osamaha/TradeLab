package com.example.core.replay

import com.example.core.model.Candle
import com.example.core.model.Tick

class ReplayBoundaryViolation(message: String) : RuntimeException(message)

/**
 * Strict data boundary for historical market replay.
 * Completely isolates the strategy, indicators, execution engine, and UI from future data.
 * Requesting any data past the current replay boundary is physically blocked.
 */
class ReplayDataView(
    private val allCandles: List<Candle>,
    private val currentIndex: Int,
    private val currentTick: Tick?
) {
    init {
        require(currentIndex in allCandles.indices || allCandles.isEmpty()) {
            "Invalid replay currentIndex: $currentIndex for total candles: ${allCandles.size}"
        }
    }

    val size: Int get() = if (allCandles.isEmpty()) 0 else currentIndex + 1

    val currentReplayTime: Long
        get() = if (allCandles.isNotEmpty() && currentIndex in allCandles.indices) {
            allCandles[currentIndex].openTime
        } else {
            0L
        }

    /**
     * Returns ONLY historical candles available at or before the current replay time.
     * Guaranteed zero lookahead.
     */
    fun getVisibleCandles(): List<Candle> {
        if (allCandles.isEmpty() || currentIndex < 0) return emptyList()
        return allCandles.subList(0, currentIndex + 1)
    }

    /**
     * Returns the candle at the specified visible index.
     * Throws [ReplayBoundaryViolation] if caller attempts to access future candles.
     */
    fun getCandleAt(index: Int): Candle {
        if (index > currentIndex) {
            throw ReplayBoundaryViolation(
                "Access Denied: Attempted to access future candle at index $index. Current replay boundary is $currentIndex (Replay Time: $currentReplayTime)."
            )
        }
        if (index < 0 || index >= allCandles.size) {
            throw IndexOutOfBoundsException("Index $index out of bounds for visible replay window.")
        }
        return allCandles[index]
    }

    /**
     * Returns the active current candle at the replay boundary.
     */
    fun getCurrentCandle(): Candle? {
        if (allCandles.isEmpty() || currentIndex !in allCandles.indices) return null
        return allCandles[currentIndex]
    }

    /**
     * Returns the current simulated tick at the replay boundary.
     */
    fun getCurrentTick(): Tick? = currentTick
}
