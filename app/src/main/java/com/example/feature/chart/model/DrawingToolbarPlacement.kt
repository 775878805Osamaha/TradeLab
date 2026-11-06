package com.example.feature.chart.model

import kotlin.math.roundToInt

/**
 * Place the inline drawing edit bar near the user's selection, keeping every
 * edge inside the visible plot. Coordinates and sizes are physical pixels.
 * This contains no chart data and does not change a drawing's anchors.
 */
internal object DrawingToolbarPlacement {
    data class Point(val x: Int, val y: Int)

    fun nearSelection(
        touchX: Float,
        touchY: Float,
        canvasWidth: Int,
        canvasHeight: Int,
        toolbarWidth: Int,
        toolbarHeight: Int,
        topInset: Int,
        gap: Int
    ): Point {
        if (canvasWidth <= 0 || canvasHeight <= 0) return Point(0, 0)
        val width = toolbarWidth.coerceIn(0, canvasWidth)
        val height = toolbarHeight.coerceIn(0, canvasHeight)
        val safeX = if (touchX.isFinite()) touchX else canvasWidth / 2f
        val safeY = if (touchY.isFinite()) touchY else canvasHeight / 2f
        val left = (safeX - width / 2f).roundToInt().coerceIn(0, canvasWidth - width)
        val inset = topInset.coerceAtLeast(0).coerceAtMost((canvasHeight - height) / 2)
        val above = safeY - height - gap
        val proposed = if (above < inset) safeY + gap else above
        val top = proposed.roundToInt().coerceIn(inset, canvasHeight - height - inset)
        return Point(left, top)
    }
}
