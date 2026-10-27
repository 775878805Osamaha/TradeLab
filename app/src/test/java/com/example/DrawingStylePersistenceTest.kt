package com.example

import androidx.compose.ui.geometry.Offset
import com.example.core.model.*
import com.example.feature.chart.model.*
import org.junit.Assert.*
import org.junit.Test

class DrawingStylePersistenceTest {
    private fun drawing()=ChartDrawing(id=9,tool=DrawingTool.RECTANGLE,symbol="XAUUSD",timeframe="M1",startTime=1_000_000,startPrice=105.0,endTime=1_060_000,endPrice=95.0,replayCreatedAt=1_000_000)
    @Test fun allStylesOpacityAndLockSurviveRoomEntityRoundTrip() {
        DrawingLineStyle.values().forEach { style ->
            val d=drawing().copy(lineStyle=style,fillOpacity=.35f,isLocked=true)
            assertEquals(d,ChartDrawing.fromEntity(d.toEntity()))
        }
    }
    @Test fun legacyRowsRetainAppearanceAndInvalidOptionalStyleIsSafe() {
        val entity=drawing().toEntity().copy(type="HORIZONTAL_LINE",pointsJson="""{"startTime":1000000,"startPrice":105.0}""")
        val legacy=ChartDrawing.fromEntity(entity)!!
        assertEquals(DrawingLineStyle.DASHED,legacy.lineStyle)
        assertFalse(legacy.isLocked)
        val malformed=entity.copy(pointsJson="""{"startTime":1000000,"startPrice":105.0,"lineStyle":"unknown","fillOpacity":20,"locked":invalid}""")
        val read=ChartDrawing.fromEntity(malformed)!!
        assertEquals(1f,read.fillOpacity,0f)
        assertFalse(read.isLocked)
        assertEquals(DrawingLineStyle.DASHED,read.lineStyle)
    }
    @Test fun lockedDrawingRejectsAnchorAndBodyMovementUntilUnlocked() {
        val candles=listOf(Candle(symbol="XAUUSD",timeframe=Timeframe.M1,openTime=1_000_000,open=100.0,high=110.0,low=90.0,close=100.0),Candle(symbol="XAUUSD",timeframe=Timeframe.M1,openTime=1_060_000,open=100.0,high=110.0,low=90.0,close=100.0))
        val t=ChartTransform(candles,90.0,110.0,400f,400f,40f)
        val d=drawing().copy(isLocked=true)
        assertEquals(d,DrawingEditing.drag(d,t,Offset(100f,100f),Offset(130f,140f),null))
        assertEquals(d,DrawingEditing.drag(d,t,Offset(100f,100f),Offset(130f,140f),0))
        assertNotEquals(d.copy(isLocked=false),DrawingEditing.drag(d.copy(isLocked=false),t,Offset(100f,100f),Offset(130f,140f),0))
    }
}
