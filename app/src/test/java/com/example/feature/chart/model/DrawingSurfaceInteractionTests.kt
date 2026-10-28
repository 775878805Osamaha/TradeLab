package com.example.feature.chart.model

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.unit.IntSize
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class DrawingSurfaceInteractionTests {
    private val candles=(0..9).map { Candle("XAUUSD",Timeframe.M1,1_000_000L+it*60_000,open=100.0,high=110.0,low=90.0,close=100.0,volume=1.0) }
    private val t=ChartTransform(candles,90.0,110.0,500f,400f,50f)
    private fun drawing(tool:DrawingTool)=ChartDrawing(id=11,symbol="XAUUSD",timeframe="M1",tool=tool,startTime=candles[2].openTime,startPrice=105.0)
    private fun anchor(d:ChartDrawing)=Offset(t.timeToX(d.startTime)!!,t.priceToY(d.startPrice))

    @Test fun imageBodyAndEdgesUseRenderedAspectRatioAtAllDensities() {
        val d=drawing(DrawingTool.IMAGE);val a=anchor(d)
        for(density in listOf(1f,1.725f,3f))for(dimensions in listOf(800 to 400,400 to 800)) {
            val size=DrawingImageGeometry.size(dimensions.first,dimensions.second,density)
            val extent=Size(size.width.toFloat(),size.height.toFloat())
            for(point in listOf(a,a+Offset(extent.width/2,extent.height/2),a+Offset(extent.width,extent.height))) {
                assertEquals(0f,DrawingHitTest.distance(d,t,point,density,extent),.001f)
            }
            assertEquals(30f,DrawingHitTest.distance(d,t,a+Offset(extent.width+30f,extent.height/2),density,extent),.001f)
            assertEquals(50f,DrawingHitTest.distance(d,t,a+Offset(extent.width+30f,extent.height+40f),density,extent),.001f)
        }
    }
    @Test fun unloadedImageFallsBackToItsAnchorWithoutInventingAnImageBox() {
        val d=drawing(DrawingTool.IMAGE);val a=anchor(d)
        assertEquals(0f,DrawingHitTest.distance(d,t,a),.001f)
        assertEquals(100f,DrawingHitTest.distance(d,t,a+Offset(100f,0f)),.001f)
    }
    @Test fun imageGeometryRejectsInvalidSourcesAndKeepsTinyImagesDrawable() {
        assertEquals(IntSize.Zero,DrawingImageGeometry.size(0,100,2f))
        assertEquals(IntSize.Zero,DrawingImageGeometry.size(100,-1,2f))
        assertEquals(IntSize.Zero,DrawingImageGeometry.size(100,100,Float.NaN))
        assertEquals(1,DrawingImageGeometry.size(10000,1,1f).height)
    }
    @Test fun draggingImageBodyPreservesTouchOffsetAndPersistsItsMarketAnchor() {
        val d=drawing(DrawingTool.IMAGE);val a=anchor(d);val touch=a+Offset(70f,35f)
        val moved=DrawingEditing.drag(d,t,touch,touch+Offset(50f,20f),null)
        assertEquals(a.x+50f,anchor(moved).x,.001f)
        assertEquals(a.y+20f,anchor(moved).y,.001f)
        assertEquals(moved,ChartDrawing.fromEntity(moved.toEntity()))
    }
    @Test fun anchoredTextBodyDoesNotJumpToTheFingerAtDragStart() {
        val d=drawing(DrawingTool.ANCHORED_TEXT).copy(screenX=.25f,screenY=.5f)
        val touch=Offset(140f,210f)
        assertEquals(d,DrawingEditing.drag(d,t,touch,touch,null))
        val moved=DrawingEditing.drag(d,t,touch,touch+Offset(50f,40f),null)
        assertEquals(.35f,moved.screenX!!,.00001f)
        assertEquals(.6f,moved.screenY!!,.00001f)
        assertEquals(d.startTime,moved.startTime)
        assertEquals(d.startPrice,moved.startPrice,0.0)
        assertEquals(moved,ChartDrawing.fromEntity(moved.toEntity()))
    }
    @Test fun anchoredTextPreviewsUseOriginalCoordinatesAndClampToScreenEdges() {
        val d=drawing(DrawingTool.ANCHORED_TEXT).copy(screenX=.25f,screenY=.5f)
        val origin=Offset(140f,210f)
        val first=DrawingEditing.drag(d,t,origin,origin+Offset(10f,10f),0)
        val second=DrawingEditing.drag(d,t,origin,origin+Offset(20f,20f),0)
        assertEquals(.27f,first.screenX!!,.00001f)
        assertEquals(.29f,second.screenX!!,.00001f)
        val clamped=DrawingEditing.drag(d,t,origin,Offset(-1000f,2000f),null)
        assertEquals(0f,clamped.screenX!!,0f);assertEquals(1f,clamped.screenY!!,0f)
    }
    @Test fun legacyAnchoredTextStartsFromItsVisibleMarketAnchor() {
        val d=drawing(DrawingTool.ANCHORED_TEXT);val a=anchor(d)
        val moved=DrawingEditing.drag(d,t,a+Offset(10f,0f),a+Offset(60f,20f),null)
        assertEquals((a.x+50f)/t.chartWidth,moved.screenX!!,.00001f)
        assertEquals((a.y+20f)/t.chartHeight,moved.screenY!!,.00001f)
    }
    @Test fun invalidOrLockedTextDragCannotCorruptSavedScreenFractions() {
        val d=drawing(DrawingTool.ANCHORED_TEXT).copy(screenX=.25f,screenY=.5f)
        assertEquals(d,DrawingEditing.drag(d,t,Offset.Zero,Offset(Float.NaN,1f),null))
        assertEquals(d,DrawingEditing.drag(d,t.copy(chartWidth=0f),Offset.Zero,Offset(20f,20f),null))
        val locked=d.copy(isLocked=true)
        assertEquals(locked,DrawingEditing.drag(locked,t,Offset.Zero,Offset(20f,20f),null))
    }
    @Test fun elongatedEllipseDoesNotSelectEmptySpaceBeyondItsMajorAxisTips() {
        val d=drawing(DrawingTool.ELLIPSE).copy(endTime=candles[8].openTime,endPrice=104.0,fillOpacity=0f)
        val a=anchor(d);val b=Offset(t.timeToX(d.endTime!!)!!,t.priceToY(d.endPrice!!))
        val tip=Offset(b.x,(a.y+b.y)/2f)
        assertEquals(50f,DrawingHitTest.distance(d,t,tip+Offset(50f,0f)),.3f)
        assertTrue(DrawingHitTest.distance(d,t,tip+Offset(50f,0f))>18f)
    }
    @Test fun ellipseOutlineSelectsEveryQuadrantAndFilledInteriorOnlyWhenEnabled() {
        val d=drawing(DrawingTool.ELLIPSE).copy(endTime=candles[8].openTime,endPrice=95.0,fillOpacity=0f)
        val a=anchor(d);val b=Offset(t.timeToX(d.endTime!!)!!,t.priceToY(d.endPrice!!));val center=(a+b)/2f
        for(angle in listOf(.4,2.2,3.8,5.4)) {
            val point=center+Offset(((b.x-a.x)/2*kotlin.math.cos(angle)).toFloat(),((b.y-a.y)/2*kotlin.math.sin(angle)).toFloat())
            assertEquals(0f,DrawingHitTest.distance(d,t,point),.3f)
        }
        assertTrue(DrawingHitTest.distance(d,t,center)>90f)
        assertEquals(0f,DrawingHitTest.distance(d.copy(fillOpacity=.2f),t,center),0f)
    }
}
