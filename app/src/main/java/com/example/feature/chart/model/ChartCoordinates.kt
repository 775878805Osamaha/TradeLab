package com.example.feature.chart.model

import kotlin.math.roundToInt

/**
 * Pixel-accurate coordinate conversion shared by chart rendering, crosshair and drawings.
 * No clipping is performed here: drawing code is responsible for canvas clipping.
 */
object ChartCoordinates {
    fun candleX(index: Int, visibleCount: Int, chartWidth: Float,
                candleWidth: Float, fractionalScroll: Float): Float {
        if (visibleCount <= 0) return 0f
        return chartWidth - (visibleCount - 1 - index) * candleWidth -
            candleWidth / 2f - fractionalScroll
    }

    fun candleIndex(x: Float, visibleCount: Int, chartWidth: Float,
                    candleWidth: Float, fractionalScroll: Float): Int {
        if (visibleCount <= 0 || !x.isFinite()) return -1
        val distance = chartWidth - x - candleWidth / 2f - fractionalScroll
        val offset = (distance / candleWidth.coerceAtLeast(1f)).roundToInt()
        return (visibleCount - 1 - offset).coerceIn(0, visibleCount - 1)
    }

    fun priceY(price: Double, minPrice: Double, maxPrice: Double,
               chartHeight: Float): Float {
        if (!price.isFinite() || !minPrice.isFinite() || !maxPrice.isFinite() ||
            maxPrice <= minPrice || chartHeight <= 0f) return chartHeight / 2f
        return (((maxPrice - price) / (maxPrice - minPrice)).coerceIn(0.0, 1.0) *
            chartHeight).toFloat()
    }

    fun yPrice(y: Float, minPrice: Double, maxPrice: Double,
               chartHeight: Float): Double {
        if (chartHeight <= 0f || maxPrice <= minPrice) return minPrice
        return maxPrice - (y / chartHeight).coerceIn(0f, 1f) * (maxPrice - minPrice)
    }
}
