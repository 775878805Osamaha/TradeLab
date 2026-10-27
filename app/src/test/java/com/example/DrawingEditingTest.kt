package com.example

import androidx.compose.ui.geometry.Offset
import com.example.core.model.*
import com.example.feature.chart.model.*
import org.junit.Assert.*
import org.junit.Test

class DrawingEditingTest {
    private val candles=(0..9).map { i->Candle(symbol="XAUUSD",timeframe=Timeframe.M1,openTime=1_000_000L+i*60_000,open=100.0,high=110.0,low=90.0,close=100.0,volume=1.0,closeTime=1_059_999L+i*60_000) }
    private val t=ChartTransform(candles,90.0,110.0,400f,400f,40f)
    private fun drawing(tool:DrawingTool)=ChartDrawing(id=7,symbol="XAUUSD",timeframe="M1",tool=tool,startTime=candles[2].openTime,startPrice=105.0,endTime=candles[6].openTime,endPrice=95.0)
    @Test fun continuousDrawingTimeSupportsFutureSpaceAndInverse() {
        for(x in listOf(20f,71f,300f,450f))assertEquals(x,t.timeToX(t.drawingTimeAtX(x))!!,.01f)
        assertTrue(t.drawingTimeAtX(450f)>candles.last().openTime)
    }
    @Test fun rectangleInteriorAndFibonacciLevelsAreSelectable() {
        assertEquals(0f,DrawingHitTest.distance(drawing(DrawingTool.RECTANGLE),t,Offset(180f,200f)),0f)
        val fib=drawing(DrawingTool.FIBONACCI)
        val level=FibonacciCalculator.calculateLevels(105.0,95.0)[3].second
        assertEquals(0f,DrawingHitTest.distance(fib,t,Offset(390f,t.priceToY(level))),.001f)
    }
    @Test fun bodyTranslationMovesBothEndsWithoutChangingPriceSpan() {
        val d=drawing(DrawingTool.TRENDLINE)
        val moved=DrawingEditing.drag(d,t,Offset(180f,200f),Offset(220f,220f),null)
        assertEquals(d.startTime+60_000,moved.startTime)
        assertEquals(d.endTime!!+60_000,moved.endTime)
        assertEquals(d.startPrice-d.endPrice!!,moved.startPrice-moved.endPrice!!,.000001)
        assertEquals(d.id,moved.id)
        assertEquals(d.symbol,moved.symbol)
    }
    @Test fun rectangleHasEightHandlesAndMidEdgeChangesOnlyOneSide() {
        val d=drawing(DrawingTool.RECTANGLE)
        val handles=DrawingEditing.handles(d,t)
        assertEquals(8,handles.size)
        val changed=DrawingEditing.drag(d,t,handles[1],handles[1]+Offset(30f,20f),1)
        assertEquals(d.startTime,changed.startTime)
        assertEquals(d.endTime,changed.endTime)
        assertEquals(d.endPrice!!,changed.endPrice!!,0.0)
        assertNotEquals(d.startPrice,changed.startPrice)
    }
    @Test fun movingOnePathAnchorPreservesOtherAnchorsAndSerialization() {
        val d=drawing(DrawingTool.TRIANGLE).copy(anchors=listOf(DrawingAnchor(candles[2].openTime,105.0),DrawingAnchor(candles[5].openTime,103.0),DrawingAnchor(candles[6].openTime,95.0)))
        val moved=DrawingEditing.drag(d,t,Offset(100f,100f),Offset(140f,120f),0)
        assertEquals(d.anchors.drop(1),moved.anchors.drop(1))
        assertEquals(moved,ChartDrawing.fromEntity(moved.toEntity()))
    }
    @Test fun freehandKeepsOnlyEndpointHandlesAndTranslatesItsWholeStroke() {
        val d=drawing(DrawingTool.BRUSH).copy(anchors=(0..5).map { DrawingAnchor(candles[it+1].openTime,101.0+it) })
        val handles=DrawingEditing.handles(d,t)
        assertEquals(2,handles.size)
        assertEquals(5,DrawingEditing.handleAt(d,t,handles.last(),10f))
        val moved=DrawingEditing.drag(d,t,Offset(100f,100f),Offset(140f,120f),null)
        assertEquals(d.anchors.size,moved.anchors.size)
        moved.anchors.forEachIndexed { i,a->assertEquals(d.anchors[i].time+60_000,a.time) }
    }
}
