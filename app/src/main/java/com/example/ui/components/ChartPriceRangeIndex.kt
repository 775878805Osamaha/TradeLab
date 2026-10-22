package com.example.ui.components

import com.example.core.model.Candle
import kotlin.math.max
import kotlin.math.min

/**
 * Immutable segment tree for fast OHLC range queries during chart gestures.
 * Build: O(n); viewport query: O(log n) without allocating candle slices.
 */
internal class ChartPriceRangeIndex(candles: List<Candle>) {
    private val length = candles.size
    private var capacity = 1
    private val lows: DoubleArray
    private val highs: DoubleArray
    private val volumes: DoubleArray

    init {
        while (capacity < length) capacity = capacity shl 1
        lows = DoubleArray(capacity * 2) { Double.POSITIVE_INFINITY }
        highs = DoubleArray(capacity * 2) { Double.NEGATIVE_INFINITY }
        volumes = DoubleArray(capacity * 2)
        candles.forEachIndexed { i, candle ->
            lows[capacity + i] = candle.low
            highs[capacity + i] = candle.high
            volumes[capacity + i] = candle.volume.coerceAtLeast(0.0)
        }
        for (i in capacity - 1 downTo 1) {
            lows[i] = min(lows[i * 2], lows[i * 2 + 1])
            highs[i] = max(highs[i * 2], highs[i * 2 + 1])
            volumes[i] = max(volumes[i * 2], volumes[i * 2 + 1])
        }
    }

    /** Fast maximum-volume lookup for the current viewport, no full scan. */
    fun maxVolume(fromInclusive: Int, toExclusive: Int): Double {
        if (length == 0 || fromInclusive >= toExclusive) return 0.0
        var left = fromInclusive.coerceIn(0, length) + capacity
        var right = toExclusive.coerceIn(0, length) + capacity
        var peak = 0.0
        while (left < right) {
            if (left and 1 == 1) peak = max(peak, volumes[left++])
            if (right and 1 == 1) peak = max(peak, volumes[--right])
            left = left shr 1
            right = right shr 1
        }
        return peak
    }

    fun query(fromInclusive: Int, toExclusive: Int): Pair<Double, Double> {
        if (length == 0 || fromInclusive >= toExclusive) return 0.0 to 1.0
        var left = fromInclusive.coerceIn(0, length) + capacity
        var right = toExclusive.coerceIn(0, length) + capacity
        if (left >= right) return 0.0 to 1.0
        var low = Double.POSITIVE_INFINITY
        var high = Double.NEGATIVE_INFINITY
        while (left < right) {
            if (left and 1 == 1) {
                low = min(low, lows[left])
                high = max(high, highs[left])
                left++
            }
            if (right and 1 == 1) {
                right--
                low = min(low, lows[right])
                high = max(high, highs[right])
            }
            left = left shr 1
            right = right shr 1
        }
        return if (low.isFinite() && high.isFinite()) low to high else 0.0 to 1.0
    }
}
