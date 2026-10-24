package com.example.feature.chart.model

import com.example.core.model.Candle

/**
 * Handles two-way conversion between Market Coordinates (Timestamp, Price)
 * and Canvas Screen Coordinates (X, Y).
 */
data class ChartTransform(
    val visibleCandles: List<Candle>,
    val minPrice: Double,
    val maxPrice: Double,
    val chartWidth: Float,
    val chartHeight: Float,
    val candleWidthPx: Float,
    val rightAxisWidth: Float = 115f,
    val fractionalScrollPx: Float = 0f
) {
    val priceSpan: Double = (maxPrice - minPrice).coerceAtLeast(0.0001)

    fun priceToY(price: Double): Float {
        if (price.isNaN() || price.isInfinite() || priceSpan <= 0.0) return chartHeight * 0.5f
        return ChartCoordinates.priceY(price, minPrice, maxPrice, chartHeight)
    }

    fun yToPrice(y: Float): Double {
        if (chartHeight <= 0f) return minPrice
        return ChartCoordinates.yPrice(y, minPrice, maxPrice, chartHeight)
    }

    fun candleIndexToX(indexInVisible: Int): Float {
        val totalVisible = visibleCandles.size
        if (totalVisible <= 0) return 0f
        // Right-aligned chart: index totalVisible - 1 is at chartWidth - (candleWidthPx / 2)
        return ChartCoordinates.candleX(indexInVisible, totalVisible, chartWidth,
            candleWidthPx, fractionalScrollPx)
    }

    fun xToCandleIndex(x: Float): Int {
        val totalVisible = visibleCandles.size
        if (totalVisible <= 0) return -1
        // Inverse of candleIndexToX: account for right-side future space.
        return ChartCoordinates.candleIndex(x, totalVisible, chartWidth,
            candleWidthPx, fractionalScrollPx)
    }

    fun timeToX(time: Long): Float? {
        if (visibleCandles.isEmpty()) return null
        val exact = visibleCandles.indexOfFirst { it.openTime == time }
        if (exact >= 0) return candleIndexToX(exact)
        val right = visibleCandles.indexOfFirst { it.openTime > time }
        if (right == 0) return candleIndexToX(0)
        if (right < 0) return candleIndexToX(visibleCandles.lastIndex)
        val left = right - 1
        val start = visibleCandles[left].openTime
        val end = visibleCandles[right].openTime
        if (end <= start) return candleIndexToX(left)
        val fraction = ((time - start).toDouble() / (end - start)).coerceIn(0.0, 1.0)
        return candleIndexToX(left) + (candleIndexToX(right) - candleIndexToX(left)) * fraction.toFloat()
    }

    fun xToTime(x: Float): Long {
        val idx = xToCandleIndex(x)
        return if (idx in visibleCandles.indices) visibleCandles[idx].openTime else System.currentTimeMillis()
    }
}
