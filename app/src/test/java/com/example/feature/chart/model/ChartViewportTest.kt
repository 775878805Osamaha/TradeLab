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

    @Test fun subCandleSwipeRemainsSmooth() {
        val before = window(-3f)
        val after = window(-4f)
        assertEquals(before.startIndex, after.startIndex)
        assertEquals(1f, after.fractionalScrollPx - before.fractionalScrollPx, 0.001f)
    }

    @Test fun zoomRecalculatesVisibleWindowWithoutInvalidIndices() {
        for (candleWidth in listOf(6f, 12f, 24f, 80f)) {
            for (offset in listOf(-500f, 0f, 18f, 250f, 10000f)) {
                val result = ChartViewport.window(300, 600f, candleWidth, offset)
                assertTrue(result.startIndex >= 0)
                assertTrue(result.endIndex <= 300)
                assertTrue(result.endIndex > result.startIndex)
            }
        }
    }

    @Test fun singleCandleIsStable() {
        val result = ChartViewport.window(1, 600f, 12f, 100f)
        assertEquals(0, result.startIndex)
        assertEquals(1, result.endIndex)
        assertEquals(0f, result.clampedOffsetPx, 0.001f)
    }

    @Test fun leftThenRightReturnsToOrigin() {
        val origin = window(0f)
        val returned = window(-150f + 150f)
        assertEquals(origin, returned)
    }
}
