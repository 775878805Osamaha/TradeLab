package com.example

import com.example.feature.chart.model.ChartDrawing
import com.example.feature.chart.model.DrawingTool
import com.example.feature.replay.visibleReplayDrawings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReplayDrawingVisibilityTests {
    private fun drawing(start: Long, end: Long? = null, price: Double = 100.0) =
        ChartDrawing(tool = DrawingTool.TRENDLINE, symbol = "BTCUSDT",
            timeframe = "M1", startPrice = price, startTime = start,
            endPrice = if (end == null) null else 110.0, endTime = end)

    @Test fun hidesFutureAnchorsAfterRewind() {
        val drawings = listOf(drawing(100L, 200L), drawing(100L, 400L), drawing(300L))
        assertEquals(1, visibleReplayDrawings(drawings, 250L).size)
        assertEquals(3, visibleReplayDrawings(drawings, 450L).size)
    }

    @Test fun rejectsInvalidPricesAndMissingReplayCandle() {
        val drawings = listOf(drawing(100L), drawing(100L, price = Double.NaN),
            drawing(100L, price = -1.0))
        assertTrue(visibleReplayDrawings(drawings, null).isEmpty())
        assertEquals(1, visibleReplayDrawings(drawings, 100L).size)
    }
    @Test fun hidesFutureAnnotationsAndIncompleteEllipsesInEmbeddedReplay() {
        val known = drawing(100L).copy(tool = DrawingTool.ANNOTATION, text = "مستوى معروف")
        val future = drawing(200L).copy(tool = DrawingTool.ANNOTATION, text = "معلومة مستقبلية")
        val ellipse = drawing(100L, 200L).copy(tool = DrawingTool.ELLIPSE)
        assertEquals(listOf(known), visibleReplayDrawings(listOf(known, future, ellipse), 150L))
        assertEquals(3, visibleReplayDrawings(listOf(known, future, ellipse), 200L).size)
    }

}
