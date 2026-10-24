package com.example.feature.chart.model

import org.junit.Assert.*
import org.junit.Test

class ChartNavigationTest {
    @Test fun leftFingerDragMovesViewportLeft() {
        assertEquals(-100f, ChartNavigation.drag(0f, -100f), 0f)
    }

    @Test fun rightFingerDragMovesViewportRight() {
        assertEquals(100f, ChartNavigation.drag(0f, 100f), 0f)
    }

    @Test fun oppositeDragsReturnToStart() {
        val left = ChartNavigation.drag(0f, -180f)
        assertEquals(0f, ChartNavigation.drag(left, 180f), 0f)
    }

    @Test fun centerLatestPlacesLastCandleInViewportMiddle() {
        val offset = ChartNavigation.centerLatestOffset(600f, 12f)
        val window = ChartViewport.window(300, 600f, 12f, offset)
        val count = window.endIndex - window.startIndex
        val lastX = ChartCoordinates.candleX(count - 1, count, 600f, 12f, window.fractionalScrollPx)
        assertEquals(300f, lastX, 0.01f)
    }

    @Test fun centerLatestRespectsDifferentZoomLevels() {
        for (candleWidth in listOf(6f, 12f, 40f, 80f)) {
            val offset = ChartNavigation.centerLatestOffset(600f, candleWidth)
            val window = ChartViewport.window(300, 600f, candleWidth, offset)
            val count = window.endIndex - window.startIndex
            val lastX = ChartCoordinates.candleX(count - 1, count, 600f, candleWidth, window.fractionalScrollPx)
            assertEquals(300f, lastX, 0.01f)
        }
    }

    @Test fun zoomInNeverExceedsLimit() {
        assertEquals(80f, ChartNavigation.zoomIn(80f), 0f)
    }

    @Test fun zoomOutNeverDropsBelowLimit() {
        assertEquals(6f, ChartNavigation.zoomOut(6f), 0f)
    }

    @Test fun zoomInAndOutApproximatelyReverse() {
        val zoomed = ChartNavigation.zoomIn(12f)
        assertEquals(12f, ChartNavigation.zoomOut(zoomed), 0.0001f)
    }

    @Test fun resetDefaultCandleWidthIsWithinBounds() {
        assertTrue(ChartNavigation.DEFAULT_CANDLE_WIDTH in
            ChartNavigation.MIN_CANDLE_WIDTH..ChartNavigation.MAX_CANDLE_WIDTH)
    }
}
