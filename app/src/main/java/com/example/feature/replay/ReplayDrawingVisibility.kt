package com.example.feature.replay

import com.example.feature.chart.model.ChartDrawing

/**
 * Only show drawings whose complete anchors are known at the current replay candle.
 * This prevents drawings placed later in a session from revealing future prices after rewind.
 */
internal fun visibleReplayDrawings(
    drawings: List<ChartDrawing>,
    revealedCandleTime: Long?
): List<ChartDrawing> {
    val cutoff = revealedCandleTime ?: return emptyList()
    return drawings.filter { drawing ->
        drawing.anchors.all { it.time <= cutoff && it.price.isFinite() && it.price > 0.0 } &&
            drawing.startTime <= cutoff &&
            (drawing.endTime == null || drawing.endTime <= cutoff) &&
            drawing.startPrice.isFinite() && drawing.startPrice > 0.0 &&
            (drawing.endPrice == null || (drawing.endPrice.isFinite() && drawing.endPrice > 0.0))
    }
}
