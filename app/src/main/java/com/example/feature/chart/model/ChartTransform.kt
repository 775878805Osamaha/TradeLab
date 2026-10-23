package com.example.feature.chart.model

import com.example.core.model.Candle
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

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
        val normalized = ((maxPrice - price) / priceSpan).coerceIn(0.0, 1.0)
        return (normalized * chartHeight).toFloat()
    }

    fun yToPrice(y: Float): Double {
        if (chartHeight <= 0f) return minPrice
        val normalized = (y / chartHeight).coerceIn(0f, 1f)
        return maxPrice - (normalized * priceSpan)
    }

    fun candleIndexToX(indexInVisible: Int): Float {
        val totalVisible = visibleCandles.size
        if (totalVisible <= 0) return 0f
        // Right-aligned chart: index totalVisible - 1 is at chartWidth - (candleWidthPx / 2)
        val xFromRight = (totalVisible - 1 - indexInVisible) * candleWidthPx
        return (chartWidth - xFromRight - (candleWidthPx / 2f) - fractionalScrollPx).coerceIn(-1000f, chartWidth + 1000f)
    }

    fun xToCandleIndex(x: Float): Int {
        val totalVisible = visibleCandles.size
        if (totalVisible <= 0) return -1
        // Inverse of candleIndexToX: account for right-side future space.
        val distFromRight = chartWidth - x - (candleWidthPx / 2f) - fractionalScrollPx
        val offset = (distFromRight / candleWidthPx.coerceAtLeast(1f)).roundToInt()
        val index = (totalVisible - 1 - offset)
        return index.coerceIn(0, totalVisible - 1)
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
