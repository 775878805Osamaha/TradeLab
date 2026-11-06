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
    @Test fun singlePointTextAndImageCanBeRepositionedFromTheirVisibleHandle() {
        for (tool in listOf(DrawingTool.TEXT,DrawingTool.IMAGE,DrawingTool.PRICE_LABEL)) {
            val original = drawing().copy(tool=tool,anchors=emptyList(),endTime=null,endPrice=null)
            assertEquals(1,DrawingAnchorEditing.points(original).size)
            val moved = DrawingAnchorEditing.move(original,0,DrawingAnchor(250,55.0))
            assertEquals(250L,moved.startTime)
            assertEquals(55.0,moved.startPrice,0.0)
        }
    }
    @Test fun movingEntirePositionPreservesItsRiskRewardGeometry() {
        val original = drawing().copy(tool=DrawingTool.LONG_POSITION)
        val moved = DrawingAnchorEditing.translate(original,50,4.5)
        assertEquals(150L,moved.startTime)
        assertEquals(14.5,moved.startPrice,0.0)
        assertEquals(original.anchors.map { it.price + 4.5 },moved.anchors.map { it.price })
        assertEquals(original.anchors.map { it.time + 50 },moved.anchors.map { it.time })
        assertEquals(original.endPrice!! + 4.5,moved.endPrice!!,0.0)
        assertSame(original,DrawingAnchorEditing.translate(original,0,-100.0))
    }
}
