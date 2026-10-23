package com.example.feature.chart.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChartViewportTest {
    private fun window(offset: Float) = ChartViewport.window(
        candleCount = 300, chartWidthPx = 600f, candleWidthPx = 12f,
        requestedOffsetPx = offset
    )

    @Test fun leftSwipeMovesCandlesLeftAndRevealsFutureSpace() {
        val initial = window(0f)
        val after = window(-180f)
        assertEquals(initial.startIndex, after.startIndex)
        assertEquals(initial.endIndex, after.endIndex)
        assertEquals(180f, after.fractionalScrollPx, 0.001f)
        // ChartTransform subtracts fractionalScrollPx from candle X.
        assertTrue(after.fractionalScrollPx > initial.fractionalScrollPx)
    }

    @Test fun rightSwipeMovesCandlesRightThroughHistory() {
        val initial = window(0f)
        val after = window(30f)
        assertEquals(initial.startIndex - 2, after.startIndex)
        assertEquals(-6f, after.fractionalScrollPx, 0.001f)
    }

    @Test fun futureSpaceClampsToSeventyPercent() {
        val after = window(-10000f)
        assertEquals(-420f, after.clampedOffsetPx, 0.001f)
        assertEquals(420f, after.fractionalScrollPx, 0.001f)
    }

    @Test fun noHistoryOverscroll() {
        val after = window(100000f)
        assertEquals(0, after.startIndex)
        assertTrue(after.endIndex <= 300)
    }

    @Test fun shortSeriesRemainsValid() {
        val after = ChartViewport.window(2, 600f, 12f, 200f)
        assertEquals(0, after.startIndex)
        assertEquals(2, after.endIndex)
        assertEquals(0f, after.clampedOffsetPx, 0.001f)
    }

    @Test fun leftThenRightReturnsToOrigin() {
        val origin = window(0f)
        val returned = window(-150f + 150f)
        assertEquals(origin, returned)
    }
}
