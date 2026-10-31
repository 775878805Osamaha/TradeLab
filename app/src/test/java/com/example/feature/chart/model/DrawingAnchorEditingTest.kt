package com.example.feature.chart.model

import org.junit.Assert.*
import org.junit.Test

class DrawingAnchorEditingTest {
    private fun drawing()=ChartDrawing(id=42,tool=DrawingTool.PARALLEL_CHANNEL,symbol="XAUUSD",timeframe="M15",
        startTime=100,startPrice=10.0,endTime=300,endPrice=30.0,
        anchors=listOf(DrawingAnchor(100,10.0),DrawingAnchor(200,20.0),DrawingAnchor(300,30.0)))
    @Test fun middleHandlePreservesOtherPointsAndMetadata() {
        val original=drawing()
        val moved=DrawingAnchorEditing.move(original,1,DrawingAnchor(220,25.0))
        assertEquals(original.copy(anchors=listOf(original.anchors[0],DrawingAnchor(220,25.0),original.anchors[2])),moved)
        assertEquals(20.0,original.anchors[1].price,0.0)
    }
    @Test fun endpointHandlesKeepStoredEndpointsConsistent() {
        val moved=DrawingAnchorEditing.move(drawing(),2,DrawingAnchor(400,40.0))
        assertEquals(400L,moved.endTime)
        assertEquals(40.0,moved.endPrice!!,0.0)
        assertEquals(DrawingAnchor(400,40.0),moved.anchors.last())
        val first=DrawingAnchorEditing.move(moved,0,DrawingAnchor(50,5.0))
        assertEquals(50L,first.startTime)
        assertEquals(5.0,first.startPrice,0.0)
    }
    @Test fun invalidCoordinatesAndUnsupportedToolsCannotBeEdited() {
        val original=drawing()
        assertSame(original,DrawingAnchorEditing.move(original,8,DrawingAnchor(100,10.0)))
        assertSame(original,DrawingAnchorEditing.move(original,1,DrawingAnchor(100,Double.NaN)))
        assertSame(original,DrawingAnchorEditing.move(original,1,DrawingAnchor(-1,10.0)))
        assertTrue(DrawingAnchorEditing.points(original.copy(tool=DrawingTool.BRUSH)).isEmpty())
    }
    @Test fun legacyTrendlineEndpointDragUpdatesOnlyRequestedHandle() {
        val original=ChartDrawing(id=17,tool=DrawingTool.TRENDLINE,symbol="XAUUSD",timeframe="M5",
            startTime=100,startPrice=2000.0,endTime=200,endPrice=2010.0)
        assertEquals(2,DrawingAnchorEditing.points(original).size)
        val changed=DrawingAnchorEditing.move(original,1,DrawingAnchor(250,2020.0))
        assertEquals(100L,changed.startTime)
        assertEquals(2000.0,changed.startPrice,0.0)
        assertEquals(250L,changed.endTime)
        assertEquals(2020.0,changed.endPrice!!,0.0)
        assertTrue(changed.anchors.isEmpty())
    }

    @Test fun invalidPriceDoesNotModifyExistingDrawing() {
        val original=drawing()
        assertSame(original,DrawingAnchorEditing.move(original,0,DrawingAnchor(120,0.0)))
        assertSame(original,DrawingAnchorEditing.move(original,0,DrawingAnchor(120,Double.POSITIVE_INFINITY)))
    }

    @Test fun draggingWholeDrawingPreservesRelativeAnchorGeometry() {
        val original=drawing()
        val shifted=DrawingAnchorEditing.translate(original,50,7.5)
        assertEquals(listOf(DrawingAnchor(150,17.5),DrawingAnchor(250,27.5),
            DrawingAnchor(350,37.5)),shifted.anchors)
        assertEquals(150L,shifted.startTime)
        assertEquals(350L,shifted.endTime)
        assertEquals(17.5,shifted.startPrice,0.0)
        assertEquals(37.5,shifted.endPrice!!,0.0)
        assertEquals(original.anchors.first(),drawing().anchors.first())
    }

    @Test fun wholeDrawingTranslationRejectsNegativePricesAndTimes() {
        val original=drawing()
        assertSame(original,DrawingAnchorEditing.translate(original,-101,0.0))
        assertSame(original,DrawingAnchorEditing.translate(original,0,-10.0))
        assertSame(original,DrawingAnchorEditing.translate(original,0,Double.NaN))
    }

    @Test fun legacyLineTranslationKeepsLegacyStorageFormat() {
        val original=ChartDrawing(id=99,tool=DrawingTool.TRENDLINE,symbol="XAUUSD",timeframe="M5",
            startTime=100,startPrice=2000.0,endTime=200,endPrice=2010.0)
        val moved=DrawingAnchorEditing.translate(original,10,5.0)
        assertTrue(moved.anchors.isEmpty())
        assertEquals(110L,moved.startTime)
        assertEquals(210L,moved.endTime)
        assertEquals(2005.0,moved.startPrice,0.0)
        assertEquals(2015.0,moved.endPrice!!,0.0)
    }

}
