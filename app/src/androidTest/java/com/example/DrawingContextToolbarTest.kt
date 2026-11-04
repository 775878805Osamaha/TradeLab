package com.example

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.feature.chart.DrawingContextToolbar
import com.example.feature.chart.model.ChartDrawing
import com.example.feature.chart.model.DrawingLineStyle
import com.example.feature.chart.model.DrawingTool
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.ui.components.CandlestickChart
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class DrawingContextToolbarTest {
    @get:Rule val compose = createComposeRule()

    @Test fun quickEditsPersistInDrawingAndDeletionWorksWithoutDialog() {
        val drawing = mutableStateOf(ChartDrawing(id = 42, tool = DrawingTool.HORIZONTAL_LINE,
            symbol = "XAUUSD", timeframe = "M15", startPrice = 3925.14, startTime = 1_730_000_000_000L))
        var deleted = false
        compose.setContent {
            MaterialTheme {
                DrawingContextToolbar(drawing.value, onUpdate = { drawing.value = it },
                    onDelete = { deleted = true }, onCopy = {}, onProperties = {}, onDismiss = {})
            }
        }
        compose.onNodeWithTag("drawing_context_toolbar").assertExists()
        compose.onNodeWithTag("drawing_edit_style").performClick()
        compose.onNodeWithText("خط متقطع ┄┄┄").performClick()
        compose.runOnIdle { assertEquals(DrawingLineStyle.DASHED, drawing.value.lineStyle) }
        compose.onNodeWithTag("drawing_edit_width").performClick()
        compose.onNodeWithText("4px").performClick()
        compose.runOnIdle { assertEquals(4f, drawing.value.strokeWidth, 0f) }
        compose.onNodeWithTag("drawing_edit_color").performClick()
        compose.onNodeWithText("أخضر").performClick()
        compose.runOnIdle { assertEquals(Color(0xFF4CAF50), drawing.value.color) }
        compose.onNodeWithTag("drawing_edit_delete").performClick()
        compose.runOnIdle { assertTrue(deleted) }
    }

    @Test fun captureRealAndroidRenderingOfSelectedDrawingAndFloatingToolbar() {
        // Test-only historical fixture. Production prices still come exclusively
        // from the configured broker, not from this instrumentation test.
        val bars = List(90) { i ->
            val base = 3920.0 + i * 0.11 + kotlin.math.sin(i * 0.8) * 1.5
            val close = base + if (i % 3 == 0) -1.3 else 0.8
            Candle(symbol = "XAUUSD", timeframe = Timeframe.M15,
                openTime = 1_730_000_000_000L + i * 900_000L,
                open = base, high = maxOf(base, close) + 0.6,
                low = minOf(base, close) - 0.6, close = close,
                volume = (i % 13 + 2).toDouble(), source = "UI_TEST_FIXTURE")
        }
        val selected = ChartDrawing(id=77,tool=DrawingTool.HORIZONTAL_LINE,
            symbol="XAUUSD",timeframe="M15",startTime=bars.last().openTime,
            startPrice=3926.0,color=Color(0xFF4CAF50))
        compose.setContent {
            MaterialTheme(colorScheme=darkColorScheme()) {
                Box(Modifier.fillMaxSize()) {
                    CandlestickChart(bars,modifier=Modifier.fillMaxSize(),
                        selectedDrawingId=selected.id,drawings=listOf(selected),
                        chartBackground=Color(0xFF030910),onUpdateDrawing={})
                    Box(Modifier.align(Alignment.Center)) {
                        DrawingContextToolbar(selected,onUpdate={},onDelete={},onCopy={},onProperties={},onDismiss={})
                    }
                }
            }
        }
        compose.onNodeWithTag("drawing_context_toolbar").assertExists()
        compose.onNodeWithTag("candlestick_canvas").assertExists()
        compose.waitForIdle()
        val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        android.os.ParcelFileDescriptor.AutoCloseInputStream(
            automation.executeShellCommand("screencap -p /sdcard/Download/drawing-context-native-test.png")
        ).use { it.readBytes() }
    }
}
