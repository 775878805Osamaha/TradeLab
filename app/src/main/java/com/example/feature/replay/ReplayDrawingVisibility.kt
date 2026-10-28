package com.example.feature.replay

import com.example.feature.chart.model.ChartDrawing

/**
 * Hide drawings created or edited after the current replay candle. Legacy drawings
 * without creation metadata retain their stricter complete-anchor cutoff.
 * This prevents drawings placed later in a session from revealing future prices after rewind.
 */
internal fun visibleReplayDrawings(
    drawings: List<ChartDrawing>,
    revealedCandleTime: Long?
): List<ChartDrawing> {
    val cutoff = revealedCandleTime ?: return emptyList()
    return drawings.filter { drawing ->
        val known=drawing.replayCreatedAt?.let { it<=cutoff } ?: (drawing.startTime<=cutoff &&
            (drawing.endTime==null || drawing.endTime<=cutoff) && drawing.anchors.all { it.time<=cutoff })
        known && drawing.anchors.all { it.price.isFinite() && it.price>0.0 } &&
            drawing.startPrice.isFinite() && drawing.startPrice>0.0 &&
            (drawing.endPrice==null || (drawing.endPrice.isFinite() && drawing.endPrice>0.0))
    }
}
