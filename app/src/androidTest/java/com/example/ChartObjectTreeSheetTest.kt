package com.example

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.feature.chart.ChartObjectTreeSheet
import com.example.feature.chart.model.ChartDrawing
import com.example.feature.chart.model.DrawingTool
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ChartObjectTreeSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun showsEmptyStateWithoutInventedDrawings() {
        compose.setContent {
            MaterialTheme {
                ChartObjectTreeSheet("XAUUSD", emptyList(), false, {}, {}, {}, {})
            }
        }
        compose.onNodeWithTag("object_tree_title").assertTextEquals("شجرة الكائنات")
        compose.onNodeWithText("لا توجد رسومات على هذا الشارت").assertIsDisplayed()
    }

    @Test fun existingDrawingCanBeEditedAndDeletedAfterConfirmation() {
        val drawing = ChartDrawing(id = 17, tool = DrawingTool.HORIZONTAL_LINE,
            symbol = "XAUUSD", timeframe = "M5", startPrice = 3927.2, startTime = 1000L)
        val edited = mutableListOf<Long>()
        val deleted = mutableListOf<Long>()
        compose.setContent {
            MaterialTheme {
                ChartObjectTreeSheet("XAUUSD", listOf(drawing), false, {},
                    { edited += it.id }, { deleted += it.id }, {})
            }
        }
        compose.waitForIdle()
        val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        android.os.ParcelFileDescriptor.AutoCloseInputStream(
            automation.executeShellCommand("screencap -p /sdcard/Download/tradelab-object-tree.png")
        ).use { it.readBytes() }
        compose.onNodeWithTag("object_tree_edit_17").performClick()
        compose.runOnIdle { assertEquals(listOf(17L), edited) }
        compose.onNodeWithTag("object_tree_delete_17").performClick()
        compose.onNodeWithText("حذف الرسم؟").assertIsDisplayed()
        compose.onNodeWithText("حذف", useUnmergedTree = true).performClick()
        compose.runOnIdle { assertEquals(listOf(17L), deleted) }
    }
}
