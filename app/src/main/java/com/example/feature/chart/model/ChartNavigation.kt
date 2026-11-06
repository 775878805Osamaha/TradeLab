package com.example.feature.chart.model

/**
 * Chart navigation actions, shared by the on-screen toolbar and gesture tests.
 * All offsets use the same convention as ChartViewport.
 */
object ChartNavigation {
    const val DEFAULT_CANDLE_WIDTH = 12f
    const val MIN_CANDLE_WIDTH = 6f
    const val MAX_CANDLE_WIDTH = 80f

    fun centerLatestOffset(chartWidthPx: Float, candleWidthPx: Float): Float =
        -(chartWidthPx / 2f - candleWidthPx / 2f).coerceAtLeast(0f)

    fun zoomIn(candleWidthPx: Float): Float =
        (candleWidthPx * 1.25f).coerceIn(MIN_CANDLE_WIDTH, MAX_CANDLE_WIDTH)

    fun zoomOut(candleWidthPx: Float): Float =
        (candleWidthPx / 1.25f).coerceIn(MIN_CANDLE_WIDTH, MAX_CANDLE_WIDTH)

    fun drag(currentOffsetPx: Float, fingerDeltaX: Float): Float =
        currentOffsetPx + fingerDeltaX

    /**
     * Keep the candle underneath the pinch centroid fixed on screen while its
     * width changes. The offset is relative to the newest candle, not the
     * oldest, so merely multiplying the width makes the whole chart jump.
     * Apply the finger translation after the anchored zoom in the same frame.
     */
    fun pinch(
        currentOffsetPx: Float,
        candleWidthPx: Float,
        chartWidthPx: Float,
        centroidX: Float,
        zoomChange: Float,
        panX: Float
    ): PinchResult {
        if (!zoomChange.isFinite() || zoomChange <= 0f ||
            !candleWidthPx.isFinite() || candleWidthPx <= 0f ||
            !currentOffsetPx.isFinite()) {
            return PinchResult(candleWidthPx, currentOffsetPx)
        }
        val nextWidth = (candleWidthPx * zoomChange).coerceIn(MIN_CANDLE_WIDTH, MAX_CANDLE_WIDTH)
        val viewportWidth = chartWidthPx.takeIf { it.isFinite() && it > 0f } ?: 1f
        val focalX = centroidX.takeIf { it.isFinite() }
            ?.coerceIn(0f, viewportWidth) ?: viewportWidth / 2f
        val distanceFromFocal = viewportWidth - focalX
        val scale = nextWidth / candleWidthPx
        val nextOffset = (currentOffsetPx + distanceFromFocal) * scale -
            distanceFromFocal + (panX.takeIf { it.isFinite() } ?: 0f)
        return PinchResult(nextWidth, nextOffset)
    }

    data class PinchResult(val candleWidthPx: Float, val scrollOffsetPx: Float)

    /** A horizontal drag on the time axis changes candle spacing around the touch. */
    fun timeAxisZoom(
        currentOffsetPx: Float,
        candleWidthPx: Float,
        chartWidthPx: Float,
        touchX: Float,
        fingerDeltaX: Float
    ): PinchResult {
        val base = chartWidthPx.takeIf { it.isFinite() && it > 0f } ?: 1f
        val factor = kotlin.math.exp((fingerDeltaX / (base * .75f)).coerceIn(-.35f, .35f))
        return pinch(currentOffsetPx, candleWidthPx, base, touchX, factor, 0f)
    }

    /** A short, bounded release glide makes fast drags feel continuous. */
    fun releaseGlideDistance(velocityPxPerSecond: Float): Float =
        if (velocityPxPerSecond.isFinite() && kotlin.math.abs(velocityPxPerSecond) >= 450f)
            (velocityPxPerSecond * 0.20f).coerceIn(-540f, 540f)
        else 0f
}
