package com.example.feature.chart.model

import kotlin.math.floor

/**
 * Pure viewport math for the candle chart.
 * The sign convention is: finger left => negative offset => candles left.
 * Finger right => positive offset => candles right / older history.
 */
object ChartViewport {
    data class Window(
        val startIndex: Int,
        val endIndex: Int,
        val fractionalScrollPx: Float,
        val clampedOffsetPx: Float
    )

    fun window(
        candleCount: Int,
        chartWidthPx: Float,
        candleWidthPx: Float,
        requestedOffsetPx: Float,
        futureSpaceRatio: Float = 0.70f
    ): Window {
        if (candleCount <= 0) return Window(0, 0, 0f, 0f)
        val width = chartWidthPx.coerceAtLeast(1f)
        val candleWidth = candleWidthPx.coerceAtLeast(1f)
        val visibleCount = (floor(width / candleWidth).toInt() + 3).coerceIn(1, candleCount)
        val maxHistory = ((candleCount - visibleCount).coerceAtLeast(0) * candleWidth)
        val maxFuture = width * futureSpaceRatio.coerceIn(0f, 0.95f)
        val offset = requestedOffsetPx.coerceIn(-maxFuture, maxHistory)
        val history = offset.coerceAtLeast(0f)
        val wholeCandles = floor(history / candleWidth).toInt()
            .coerceIn(0, (candleCount - visibleCount).coerceAtLeast(0))
        val fractional = if (offset < 0f) -offset else -(history - wholeCandles * candleWidth)
        val start = (candleCount - visibleCount - wholeCandles).coerceIn(0, candleCount - 1)
        return Window(start, (start + visibleCount).coerceAtMost(candleCount), fractional, offset)
    }
}
