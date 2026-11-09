package com.example

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.feature.chart.model.ChartDrawing
import com.example.feature.chart.model.DrawingTool
import com.example.ui.components.CandlestickChart
import com.example.ui.components.ChartFirstVisibleIndex
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class DrawingAnchorInteractionTest {
    @get:Rule val compose=createComposeRule()

    @Test fun tappingDrawingSelectsItAndBackgroundTapDismissesContext() {
        val bars=List(80) { i -> Candle("XAUUSD",Timeframe.M1,1_700_000_040_000L+i*60_000L,
            open=2000.0,high=2010.0,low=1990.0,close=2000.0,volume=1.0,source="TEST_FIXTURE") }
        val selected=mutableStateOf<Long?>(null)
        val line=ChartDrawing(id=17L,tool=DrawingTool.HORIZONTAL_LINE,symbol="XAUUSD",timeframe="M1",
            startTime=bars.last().openTime,startPrice=2000.0)
        compose.setContent { MaterialTheme {
            CandlestickChart(bars,drawings=listOf(line),selectedDrawingId=selected.value,
                isVolumeVisible=false,
                modifier=Modifier.fillMaxSize(),onSelectDrawing={drawing,_->selected.value=drawing.id},
                onClearDrawingSelection={selected.value=null},onUpdateDrawing={})
        } }
        val chart=compose.onNodeWithTag("candlestick_canvas")
        chart.performTouchInput { click(center) }
        compose.runOnIdle { assertEquals(17L,selected.value) }
        chart.performTouchInput { click(Offset(center.x, 15f)) }
        compose.runOnIdle { assertNull(selected.value) }
    }

    @Test fun draggingCreatedHorizontalAnchorSavesOnceWithoutPanning() {
        val bars=List(300) { i -> Candle("XAUUSD",Timeframe.M1,1_700_000_040_000L+i*60_000L,
            open=2000.0,high=2005.0,low=1995.0,close=2001.0,volume=1.0,source="TEST_FIXTURE") }
        val drawings=mutableStateOf<List<ChartDrawing>>(emptyList())
        val selectedDrawingId=mutableStateOf<Long?>(null)
        val tool=mutableStateOf(DrawingTool.HORIZONTAL_LINE)
        var writes=0
        compose.setContent { MaterialTheme { CandlestickChart(bars,drawings=drawings.value,
            selectedDrawingId=selectedDrawingId.value,
            activeDrawingTool=tool.value,modifier=Modifier.fillMaxSize(),
            onAddDrawing={drawings.value=listOf(it.copy(id=42,symbol="XAUUSD",timeframe="M1"));tool.value=DrawingTool.NONE},
            onSelectDrawing={drawing,_->selectedDrawingId.value=drawing.id},
            onUpdateDrawing={writes++;drawings.value=listOf(it)}) } }
        val canvas=compose.onNodeWithTag("candlestick_canvas")
        canvas.performTouchInput { click(center) }
        compose.waitForIdle()
        assertEquals(1,drawings.value.size)
        val original=drawings.value.single()
        canvas.performTouchInput { click(center) }
        compose.waitForIdle()
        assertEquals(42L, selectedDrawingId.value)
        val first=canvas.fetchSemanticsNode().config[ChartFirstVisibleIndex]
        canvas.performTouchInput { swipe(center,center+Offset(0f,-80f),600) }
        compose.waitForIdle()
        assertEquals(1,writes)
        assertTrue(drawings.value.single().startPrice>original.startPrice)
        assertEquals(first,canvas.fetchSemanticsNode().config[ChartFirstVisibleIndex])
    }

    @Test fun newDrawingCanBeSelectedAsSoonAsPlacementCompletes() {
        val bars=List(80) { i -> Candle("XAUUSD",Timeframe.M1,1_700_000_040_000L+i*60_000L,
            open=2000.0,high=2005.0,low=1995.0,close=2001.0,volume=1.0,source="TEST_FIXTURE") }
        val drawings=mutableStateOf<List<ChartDrawing>>(emptyList())
        val selected=mutableStateOf<Long?>(null)
        val tool=mutableStateOf(DrawingTool.HORIZONTAL_LINE)
        compose.setContent { MaterialTheme {
            Box {
                CandlestickChart(bars,drawings=drawings.value,selectedDrawingId=selected.value,
                    activeDrawingTool=tool.value,modifier=Modifier.fillMaxSize(),
                    onAddDrawing={ drawing ->
                        val stored=drawing.copy(id=33L,symbol="XAUUSD",timeframe="M1")
                        drawings.value=listOf(stored)
                        tool.value=DrawingTool.NONE
                        selected.value=stored.id
                    },onUpdateDrawing={})
            }
        } }
        compose.onNodeWithTag("candlestick_canvas").performTouchInput { click(center) }
        compose.waitForIdle()
        assertEquals(DrawingTool.NONE,tool.value)
        assertEquals(33L,selected.value)
        assertEquals(1,drawings.value.size)
    }
}
