package com.example.feature.chart.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DrawingToolbarPlacementTest {
    @Test fun selectedLineInMiddleShowsInlineBarDirectlyAboveTouch() {
        val position = DrawingToolbarPlacement.nearSelection(
            touchX = 480f, touchY = 670f,
            canvasWidth = 960, canvasHeight = 1400,
            toolbarWidth = 720, toolbarHeight = 120,
            topInset = 140, gap = 40
        )
        assertEquals(120, position.x)
        assertEquals(510, position.y)
    }

    @Test fun selectedObjectsNearEveryEdgeCannotPushToolbarOffScreen() {
        val width = 960
        val height = 1400
        val toolWidth = 720
        val toolHeight = 120
        for (x in listOf(-200f, 0f, 40f, 480f, 910f, 1200f)) {
            for (y in listOf(-100f, 0f, 160f, 700f, 1370f, 1700f)) {
                val position = DrawingToolbarPlacement.nearSelection(x, y,
                    width, height, toolWidth, toolHeight, 140, 40)
                assertTrue(position.x >= 0 && position.x + toolWidth <= width)
                assertTrue(position.y >= 140 && position.y + toolHeight <= height - 140)
            }
        }
    }

    @Test fun nearTopSelectionMovesBarBelowHandleInsteadOfCoveringIt() {
        val position = DrawingToolbarPlacement.nearSelection(
            100f, 170f, 960, 1400, 720, 120, 140, 40)
        assertEquals(0, position.x)
        assertEquals(210, position.y)
    }

    @Test fun invalidMeasurementAndNonFiniteTouchRemainSafe() {
        assertEquals(DrawingToolbarPlacement.Point(0, 0),
            DrawingToolbarPlacement.nearSelection(0f, 0f, 0, 0, 500, 100, 120, 20))
        val safe = DrawingToolbarPlacement.nearSelection(Float.NaN, Float.POSITIVE_INFINITY,
            200, 150, 400, 180, 30, 20)
        assertEquals(0, safe.x)
        assertEquals(0, safe.y)
    }
}
