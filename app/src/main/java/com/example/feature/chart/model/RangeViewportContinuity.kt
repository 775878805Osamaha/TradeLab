package com.example.feature.chart.model

import com.example.core.model.Candle
import kotlin.math.abs

/**
 * Preserves the candle the user was looking at when a bounded historical
 * Range window rolls backwards. An explicit jump to an unrelated date starts
 * at the newest bar of the newly selected window instead.
 */
object RangeViewportContinuity {
    fun offsetAfterWindowChange(
        previous: List<Candle>, current: List<Candle>,
        viewportWidthPx: Float, candleWidthPx: Float, previousOffsetPx: Float
    ): Float {
        if (previous.isEmpty() || current.isEmpty() ||
            !viewportWidthPx.isFinite() || viewportWidthPx <= 0f ||
            !candleWidthPx.isFinite() || candleWidthPx <= 0f) return 0f

        val oldFirst = previous.first().openTime
        val oldLast = previous.last().closeTime
        val newFirst = current.first().openTime
        val newLast = current.last().closeTime
        if (newLast < oldFirst || newFirst > oldLast) return 0f

        val oldViewport = ChartViewport.window(previous.size, viewportWidthPx,
            candleWidthPx, previousOffsetPx)
        val anchorIndex = (oldViewport.startIndex + oldViewport.endIndex - 1) / 2
        val anchor = previous[anchorIndex]
        val anchorTime = anchor.openTime
        if (anchorTime < newFirst || anchorTime > newLast) return 0f

        val nearest = findAnchorIndex(current, anchor)
        val visibleCount = oldViewport.endIndex - oldViewport.startIndex
        val anchorPosition = anchorIndex - oldViewport.startIndex
        val wantedStartIndex = nearest - anchorPosition
        val wantedScrollBars = current.size - visibleCount - wantedStartIndex
        return ChartViewport.window(current.size, viewportWidthPx, candleWidthPx,
            wantedScrollBars * candleWidthPx).clampedOffsetPx
    }

    /** Range opening times are NOT stable after the real quote history is
     * extended backwards. Match actual time coverage first, then nearest
     * price. Both boundaries are sorted for genuine broker-built Range bars. */
    internal fun findAnchorIndex(current: List<Candle>, anchor: Candle): Int {
        require(current.isNotEmpty())
        val anchorTime = anchor.openTime
        var left = 0
        var right = current.lastIndex
        while (left < right) {
            val mid = (left + right) ushr 1
            if (current[mid].openTime < anchorTime) left = mid + 1 else right = mid
        }
        var nearest = if (left > 0 &&
            abs(current[left - 1].openTime - anchorTime) <
                abs(current[left].openTime - anchorTime)) left - 1 else left

        // Exact timestamp duplicates can represent several different real
        // price changes within the same millisecond; never pick arbitrarily.
        if (current[left].openTime == anchorTime) {
            var candidate = left
            var bestScore = Double.POSITIVE_INFINITY
            while (candidate < current.size && current[candidate].openTime == anchorTime) {
                val bar = current[candidate]
                if (bar.source == anchor.source) {
                    if (bar.open == anchor.open && bar.close == anchor.close &&
                        bar.high == anchor.high && bar.low == anchor.low) {
                        nearest = candidate
                        return nearest
                    }
                    val distance = abs(bar.open - anchor.open) + abs(bar.close - anchor.close)
                    if (distance < bestScore) {
                        bestScore = distance
                        nearest = candidate
                    }
                }
                candidate++
            }
        }
        // A regrouped bar may begin earlier than the inspected candle while
        // still containing the exact observed quote time. Find overlapping
        // bars through binary search on their nondecreasing close times.
        left = 0
        right = current.lastIndex
        while (left < right) {
            val mid = (left + right) ushr 1
            if (current[mid].closeTime <= anchorTime) left = mid + 1 else right = mid
        }
        var bestScore = Double.POSITIVE_INFINITY
        var candidate = left
        while (candidate < current.size && current[candidate].openTime <= anchorTime) {
            val bar = current[candidate]
            if (bar.source == anchor.source && anchorTime < bar.closeTime) {
                val score = abs(bar.close - anchor.close) + abs(bar.open - anchor.open)
                if (score < bestScore) { bestScore = score; nearest = candidate }
            }
            candidate++
        }
        return nearest
    }
}
