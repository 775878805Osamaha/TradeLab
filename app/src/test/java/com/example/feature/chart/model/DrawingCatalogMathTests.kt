package com.example.feature.chart.model

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.feature.replay.visibleReplayDrawings
import org.junit.Assert.*
import org.junit.Test

class DrawingCatalogMathTests {
    private fun candle(time:Long, price:Double, vol:Double=1.0) = Candle("XAUUSD",Timeframe.M15,time,open=price,high=price,low=price,close=price,volume=vol)
    @Test fun multiPointAnchorsPersistWithoutChangingLegacyFields() {
        val points=listOf(DrawingAnchor(900000L,4000.0),DrawingAnchor(1800000L,4012.0),DrawingAnchor(2700000L,3999.0))
        val d=ChartDrawing(tool=DrawingTool.TRIANGLE,symbol="XAUUSD",timeframe="M15",startTime=points[0].time,startPrice=points[0].price,endTime=points.last().time,endPrice=points.last().price,anchors=points)
        val restored=ChartDrawing.fromEntity(d.toEntity())!!
        assertEquals(points,restored.anchors);assertEquals(d.startTime,restored.startTime)
    }
    @Test fun intermediateFutureAnchorCannotLeakIntoRewoundReplay() {
        val d=ChartDrawing(tool=DrawingTool.TRIANGLE,symbol="XAUUSD",timeframe="M15",startTime=1,startPrice=4000.0,endTime=2,endPrice=4001.0,anchors=listOf(DrawingAnchor(1,4000.0),DrawingAnchor(9,4010.0),DrawingAnchor(2,4001.0)))
        assertTrue(visibleReplayDrawings(listOf(d),5).isEmpty())
        assertEquals(1,visibleReplayDrawings(listOf(d),9).size)
    }
    @Test fun anchorPositionOutsideViewportUsesActualHistoryIndex() {
        val all=listOf(candle(900000,4000.0),candle(1800000,4001.0),candle(99900000,4002.0),candle(100800000,4003.0))
        val t=ChartTransform(all.takeLast(2),3900.0,4100.0,300f,500f,10f,allCandles=all)
        assertEquals(t.candleIndexToX(0)-20f,t.timeToX(all.first().openTime)!!,.001f)
        assertEquals(all.last().openTime,t.xToTime(1000f))
    }
    @Test fun vwapUsesAllAvailableAnchorHistoryAndRealVolumeWeights() {
        val all=listOf(candle(900000,10.0,1.0),candle(1800000,20.0,3.0),candle(2700000,99.0,0.0))
        val points=AnchoredVwap.calculate(all,900000)
        assertEquals(2,points.size);assertEquals(17.5,points.last().price,.0001)
        assertEquals(20.0,AnchoredVwap.calculate(all,1800000).last().price,.0001)
    }
    @Test fun missingAnchorHistoryOrMissingVolumeNeverInventsVwap() {
        assertTrue(AnchoredVwap.calculate(listOf(candle(1800000,10.0)),900000).isEmpty())
        assertTrue(AnchoredVwap.calculate(listOf(candle(900000,10.0,0.0)),900000).isEmpty())
    }
    @Test fun smallPricesSurviveScientificNotationPersistence() {
        val d=ChartDrawing(tool=DrawingTool.HORIZONTAL_LINE,symbol="TEST",timeframe="M15",startTime=900000,startPrice=.0000003)
        assertEquals(d.startPrice,ChartDrawing.fromEntity(d.toEntity())!!.startPrice,1e-14)
    }
    @Test fun anchoredTextRetainsScreenFractionsAcrossPersistence() {
        val d=ChartDrawing(tool=DrawingTool.ANCHORED_TEXT,symbol="XAUUSD",timeframe="M15",startTime=900000,startPrice=4000.0,screenX=.25f,screenY=.75f,text="ملاحظة")
        val restored=ChartDrawing.fromEntity(d.toEntity())!!
        assertEquals(.25f,restored.screenX!!,0f);assertEquals(.75f,restored.screenY!!,0f)
    }

}
