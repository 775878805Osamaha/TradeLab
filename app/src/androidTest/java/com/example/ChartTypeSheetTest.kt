package com.example

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.feature.chart.ChartTypeCatalog
import com.example.feature.chart.ChartTypeSheet
import com.example.ui.components.ChartDisplayStyle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ChartTypeSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun arabicReferenceGridKeepsThreeColumnsAndEveryTypeInOrder() {
        assertEquals(21, ChartTypeCatalog.options.size)
        assertEquals(listOf("bars", "candles", "hollow"), ChartTypeCatalog.options.take(3).map { it.key })
        assertEquals(listOf("kagi", "point_figure", "range"), ChartTypeCatalog.options.takeLast(3).map { it.key })
        val current = mutableStateOf(ChartDisplayStyle.CANDLES)
        var unavailable: String? = null
        compose.setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize().background(Color(0xFFEDEDED))) {
                    ChartTypeSheet(current.value, onSelect = { current.value = it },
                        onUnavailable = { unavailable = it }, onDismiss = {})
                }
            }
        }
        compose.onNodeWithTag("chart_type_sheet_title").assertTextEquals("نوع الرسم البياني")
        compose.onNodeWithTag("chart_type_bars").assertExists()
        compose.onNodeWithTag("chart_type_candles").assertExists()
        compose.onNodeWithTag("chart_type_hollow").assertExists()
        compose.onNodeWithTag("chart_type_area").performClick()
        compose.runOnIdle { assertEquals(ChartDisplayStyle.AREA, current.value) }
        compose.onNodeWithTag("chart_type_grid")
            .performScrollToNode(hasTestTag("chart_type_range"))
        compose.onNodeWithTag("chart_type_range").performClick()
        compose.runOnIdle {
            assertEquals(null, unavailable)
            assertEquals(ChartDisplayStyle.RANGE, current.value)
        }
    }

    @Test fun captureNativeArabicChartTypeSheet() {
        compose.setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize().background(Color(0xFFFAFAFA))) {
                    ChartTypeSheet(ChartDisplayStyle.CANDLES, onSelect = {},
                        onUnavailable = {}, onDismiss = {})
                }
            }
        }
        compose.onNodeWithTag("chart_type_grid").assertExists()
        compose.waitUntil(timeoutMillis = 7_000) {
            runCatching {
                compose.onNodeWithTag("chart_type_sheet_title").assertIsDisplayed()
            }.isSuccess
        }
        compose.waitForIdle()
        // ModalBottomSheet's presentation animation can continue after semantics become visible.
        // Screenshot timing must be deterministic on slow CI emulator renderers.
        Thread.sleep(900)
        val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val screenshot = requireNotNull(automation.takeScreenshot())
        var darkContentPixels = 0
        for (y in screenshot.height / 6 until screenshot.height * 5 / 6 step 16) {
            for (x in screenshot.width / 8 until screenshot.width * 7 / 8 step 16) {
                val pixel = screenshot.getPixel(x, y)
                if (android.graphics.Color.red(pixel) < 110 &&
                    android.graphics.Color.green(pixel) < 110 &&
                    android.graphics.Color.blue(pixel) < 110
                ) darkContentPixels++
            }
        }
        assertTrue("Chart type title and icons must be visible in the native capture", darkContentPixels > 30)
        android.os.ParcelFileDescriptor.AutoCloseInputStream(
            automation.executeShellCommand("screencap -p /sdcard/Download/tradelab-chart-type-sheet.png")
        ).use { it.readBytes() }
    }
}
