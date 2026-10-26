package com.example.feature.chart.model

import androidx.compose.ui.geometry.Offset
import kotlin.math.abs

/** Snap only to revealed, visible OHLC values. Does not query history or reset the viewport. */
fun ChartTransform.snapDrawingPoint(point: Offset, enabled: Boolean): Offset {
    if (!enabled || visibleCandles.isEmpty()) return point
    val index = xToCandleIndex(point.x).coerceIn(visibleCandles.indices)
    val candle = visibleCandles[index]
    val price = yToPrice(point.y)
    val nearest = listOf(candle.open, candle.high, candle.low, candle.close).minBy { abs(it - price) }
    return Offset(candleIndexToX(index), priceToY(nearest))
}
