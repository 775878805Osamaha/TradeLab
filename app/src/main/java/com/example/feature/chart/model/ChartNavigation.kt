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
}
