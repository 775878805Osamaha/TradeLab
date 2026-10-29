package com.example

import androidx.compose.foundation.layout.fillMaxSize
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
    @Test fun draggingCreatedHorizontalAnchorSavesOnceWithoutPanning() {
        val bars=List(300) { i -> Candle("XAUUSD",Timeframe.M1,1_700_000_040_000L+i*60_000L,
            open=2000.0,high=2005.0,low=1995.0,close=2001.0,volume=1.0,source="TEST_FIXTURE") }
        val drawings=mutableStateOf<List<ChartDrawing>>(emptyList())
        val tool=mutableStateOf(DrawingTool.HORIZONTAL_LINE)
        var writes=0
        compose.setContent { MaterialTheme { CandlestickChart(bars,drawings=drawings.value,
            activeDrawingTool=tool.value,modifier=Modifier.fillMaxSize(),
            onAddDrawing={drawings.value=listOf(it.copy(id=42,symbol="XAUUSD",timeframe="M1"));tool.value=DrawingTool.NONE},
            onUpdateDrawing={writes++;drawings.value=listOf(it)}) } }
        val canvas=compose.onNodeWithTag("candlestick_canvas")
        canvas.performTouchInput { click(center) }
        compose.waitForIdle()
        assertEquals(1,drawings.value.size)
        val original=drawings.value.single()
        val first=canvas.fetchSemanticsNode().config[ChartFirstVisibleIndex]
        canvas.performTouchInput { swipe(center,center+Offset(0f,-80f),600) }
        compose.waitForIdle()
        assertEquals(1,writes)
        assertTrue(drawings.value.single().startPrice>original.startPrice)
        assertEquals(first,canvas.fetchSemanticsNode().config[ChartFirstVisibleIndex])
    }
}
