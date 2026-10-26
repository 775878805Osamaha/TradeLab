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
    val fractionalScrollPx: Float = 0f,
    val allCandles: List<Candle> = visibleCandles
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
        fun indexAt(value: Long): Double {
            val found = allCandles.binarySearchBy(value) { it.openTime }
            if (found >= 0) return found.toDouble()
            val right = -found - 1
            val interval = (visibleCandles.first().timeframe.minutes * 60_000L).coerceAtLeast(1L)
            if (right == 0) return (value - allCandles.first().openTime).toDouble() / interval
            if (right >= allCandles.size) return allCandles.lastIndex + (value - allCandles.last().openTime).toDouble() / interval
            val left = right - 1
            return left + (value - allCandles[left].openTime).toDouble() / (allCandles[right].openTime - allCandles[left].openTime).coerceAtLeast(1L)
        }
        val index = indexAt(time) - indexAt(visibleCandles.first().openTime)
        return candleIndexToX(0) + index.toFloat() * candleWidthPx
    }

    fun xToTime(x: Float): Long {
        val idx = xToCandleIndex(x)
        return if (idx in visibleCandles.indices) visibleCandles[idx].openTime else visibleCandles.getOrNull(idx.coerceIn(0, visibleCandles.lastIndex.coerceAtLeast(0)))?.openTime ?: 0L
    }
}
