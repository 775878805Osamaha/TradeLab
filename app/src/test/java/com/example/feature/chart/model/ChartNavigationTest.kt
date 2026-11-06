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

    private fun barsBehindLatestAt(x: Float, viewport: Float, candleWidth: Float, offset: Float): Float =
        (viewport - candleWidth / 2f + offset - x) / candleWidth

    @Test fun pinchKeepsFocalCandleStableAtLeftCenterAndRight() {
        for (x in listOf(55f, 300f, 555f)) {
            val before = barsBehindLatestAt(x, 600f, 12f, 160f)
            val after = ChartNavigation.pinch(160f, 12f, 600f, x, 1.5f, 0f)
            assertEquals(18f, after.candleWidthPx, 0.0001f)
            assertEquals(before, barsBehindLatestAt(x, 600f, after.candleWidthPx, after.scrollOffsetPx), 0.0001f)
        }
    }

    @Test fun zoomingBackOutRestoresTheOriginalOffset() {
        val zoomed = ChartNavigation.pinch(120f, 12f, 650f, 180f, 2f, 0f)
        val restored = ChartNavigation.pinch(zoomed.scrollOffsetPx, zoomed.candleWidthPx,
            650f, 180f, .5f, 0f)
        assertEquals(12f, restored.candleWidthPx, 0.001f)
        assertEquals(120f, restored.scrollOffsetPx, 0.001f)
    }

    @Test fun twoFingerTranslationMovesWithTheFingersWithoutChangingZoom() {
        val after = ChartNavigation.pinch(40f, 12f, 600f, 250f, 1f, -85f)
        assertEquals(12f, after.candleWidthPx, 0f)
        assertEquals(-45f, after.scrollOffsetPx, 0.0001f)
    }

    @Test fun pinchAtZoomLimitsUsesActualClampedZoomRatio() {
        val after = ChartNavigation.pinch(100f, 79f, 600f, 400f, 3f, 0f)
        assertEquals(80f, after.candleWidthPx, 0f)
        val beforeBars = barsBehindLatestAt(400f, 600f, 79f, 100f)
        val afterBars = barsBehindLatestAt(400f, 600f, after.candleWidthPx, after.scrollOffsetPx)
        assertEquals(beforeBars, afterBars, 0.0001f)
        val min = ChartNavigation.pinch(0f, 6f, 600f, 300f, .1f, 0f)
        assertEquals(6f, min.candleWidthPx, 0f)
        assertEquals(0f, min.scrollOffsetPx, 0f)
    }

    @Test fun invalidPinchDoesNotMakeViewportNonFinite() {
        val badZoom = ChartNavigation.pinch(100f, 12f, 600f, 300f, Float.NaN, 10f)
        assertEquals(12f, badZoom.candleWidthPx, 0f)
        assertEquals(100f, badZoom.scrollOffsetPx, 0f)
        val badPosition = ChartNavigation.pinch(100f, 12f, 600f, Float.NaN, 1.2f, Float.NaN)
        assertTrue(badPosition.scrollOffsetPx.isFinite())
    }

    @Test fun draggingTimeAxisZoomsAtTheTouchedTimestamp() {
        val start = barsBehindLatestAt(180f, 600f, 12f, 50f)
        val closer = ChartNavigation.timeAxisZoom(50f, 12f, 600f, 180f, 120f)
        assertTrue(closer.candleWidthPx > 12f)
        assertEquals(start,
            barsBehindLatestAt(180f, 600f, closer.candleWidthPx, closer.scrollOffsetPx), .001f)
        val restored = ChartNavigation.timeAxisZoom(closer.scrollOffsetPx, closer.candleWidthPx,
            600f, 180f, -120f)
        assertEquals(12f, restored.candleWidthPx, .001f)
        assertEquals(50f, restored.scrollOffsetPx, .001f)
    }

    @Test fun slowTouchReleaseStopsExactlyAtTheFinger() {
        assertEquals(0f, ChartNavigation.releaseGlideDistance(300f), 0f)
        assertEquals(0f, ChartNavigation.releaseGlideDistance(-300f), 0f)
    }

    @Test fun fastReleaseGlidesInTheDragDirectionAndHasASafeLimit() {
        assertEquals(200f, ChartNavigation.releaseGlideDistance(1_000f), 0.001f)
        assertEquals(-200f, ChartNavigation.releaseGlideDistance(-1_000f), 0.001f)
        assertEquals(540f, ChartNavigation.releaseGlideDistance(8_000f), 0f)
        assertEquals(-540f, ChartNavigation.releaseGlideDistance(-8_000f), 0f)
        assertEquals(0f, ChartNavigation.releaseGlideDistance(Float.NaN), 0f)
    }
}
