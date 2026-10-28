package com.example.feature.chart.model

import androidx.compose.ui.geometry.Offset
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class DrawingCurvedSelectionTests {
    private val candles=(1L..9L).map { Candle("XAUUSD",Timeframe.M15,it*900000,open=4000.0,high=4100.0,low=3900.0,close=4000.0,volume=1.0) }
    private val transform=ChartTransform(candles,3900.0,4100.0,500f,500f,50f)
    private val anchors=listOf(DrawingAnchor(900000,3920.0),DrawingAnchor(4500000,4080.0),DrawingAnchor(8100000,3920.0))
    private fun drawing(tool:DrawingTool,points:List<DrawingAnchor> = anchors)=ChartDrawing(tool=tool,symbol="XAUUSD",timeframe="M15",startTime=points.first().time,startPrice=points.first().price,endTime=points.last().time,endPrice=points.last().price,anchors=points,fillOpacity=0f)
    private fun pixel(p:DrawingAnchor)=Offset(transform.timeToX(p.time)!!,transform.priceToY(p.price))
    private fun distance(d:ChartDrawing,p:Offset)=DrawingHitTest.distance(d,transform,p)

    @Test fun curvedToolsSelectTheVisibleCurveAndRejectItsControlPolygon() {
        val a=pixel(anchors[0]);val b=pixel(anchors[1]);val c=pixel(anchors[2])
        for(tool in listOf(DrawingTool.CURVE,DrawingTool.ARC)) {
            val d=drawing(tool)
            assertTrue(distance(d,(a+b*2f+c)/4f)<1f)
            assertTrue(distance(d,(a+b)/2f)>30f)
            assertTrue(distance(d,b)>30f)
        }
    }
    @Test fun doubleCurveIncludesBothRenderedQuadratics() {
        val points=anchors+listOf(DrawingAnchor(4500000,3900.0),DrawingAnchor(900000,3920.0))
        val d=drawing(DrawingTool.DOUBLE_CURVE,points)
        assertTrue(distance(d,(pixel(points[2])+pixel(points[3])*2f+pixel(points[4]))/4f)<1f)
    }
    @Test fun channelSelectsParallelAndMiddleLinesWithoutSelectingItsConnector() {
        val d=drawing(DrawingTool.PARALLEL_CHANNEL)
        val a=pixel(anchors[0]);val b=pixel(anchors[1]);val c=pixel(anchors[2]);val shift=c-b
        assertEquals(0f,distance(d,(a+b)/2f+shift),.001f)
        assertEquals(0f,distance(d,(a+b)/2f+shift/2f),.001f)
        assertTrue(distance(d,b+(c-b)/4f)>20f)
    }
    @Test fun fanSelectsIntermediateRenderedLevel() {
        val d=drawing(DrawingTool.FIB_FAN)
        val a=pixel(anchors[0]);val b=pixel(anchors.last())
        // Use differing end prices so the fan has genuinely distinct spokes.
        val changed=d.copy(endPrice=4080.0)
        val end=Offset(b.x,transform.priceToY(4080.0))
        val level=FibonacciCalculator.DEFAULT_LEVELS.first { it>0.0 && it<1.0 }
        val spoke=Offset(end.x,(a.y+(end.y-a.y)*level).toFloat())
        assertEquals(0f,distance(changed,(a+spoke)/2f),.001f)
    }
    @Test fun cyclesSelectRepeatedVerticalLinesAndRejectMidwaySpace() {
        val d=drawing(DrawingTool.CYCLES,anchors.take(2))
        val a=pixel(anchors[0]);val b=pixel(anchors[1]);val interval=kotlin.math.abs(b.x-a.x)
        val first=a.x%interval
        assertEquals(0f,distance(d,Offset(first+interval,50f)),.001f)
        assertTrue(distance(d,Offset(first+interval/2f,50f))>20f)
    }
    @Test fun collinearControlBeyondEndpointsKeepsTheCurvesOvershootSelectable() {
        val points=listOf(DrawingAnchor(900000,4000.0),DrawingAnchor(8100000,4000.0),DrawingAnchor(2700000,4000.0))
        val d=drawing(DrawingTool.CURVE,points)
        val at=(pixel(points[0])+pixel(points[1])*2f+pixel(points[2]))/4f
        assertTrue(distance(d,at)<1f)
    }
    @Test fun coincidentCurveAnchorsRemainSelectableWithoutNaN() {
        val d=drawing(DrawingTool.CURVE,List(3){anchors.first()})
        assertEquals(0f,distance(d,pixel(anchors.first())),.001f)
        assertTrue(distance(d,Offset.Zero).isFinite())
    }
}
