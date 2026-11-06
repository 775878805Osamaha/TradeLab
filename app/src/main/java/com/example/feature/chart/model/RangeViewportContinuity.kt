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
        val anchorTime = previous[anchorIndex].openTime
        if (anchorTime < newFirst || anchorTime > newLast) return 0f

        // Range bars can be regrouped after an older genuine tick is loaded.
        // Find the nearest real timestamp instead of assuming matching indices.
        var left = 0
        var right = current.lastIndex
        while (left < right) {
            val mid = (left + right) ushr 1
            if (current[mid].openTime < anchorTime) left = mid + 1 else right = mid
        }
        val nearest = if (left > 0 &&
            abs(current[left - 1].openTime - anchorTime) <
                abs(current[left].openTime - anchorTime)) left - 1 else left
        val visibleCount = oldViewport.endIndex - oldViewport.startIndex
        val anchorPosition = anchorIndex - oldViewport.startIndex
        val wantedStartIndex = nearest - anchorPosition
        val wantedScrollBars = current.size - visibleCount - wantedStartIndex
        return ChartViewport.window(current.size, viewportWidthPx, candleWidthPx,
            wantedScrollBars * candleWidthPx).clampedOffsetPx
    }
}
