package com.example

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.feature.chart.DrawingContextToolbar
import com.example.feature.chart.model.ChartDrawing
import com.example.feature.chart.model.DrawingLineStyle
import com.example.feature.chart.model.DrawingTool
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
}
