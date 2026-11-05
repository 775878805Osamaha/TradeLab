package com.example

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.feature.chart.FibonacciSettingsScreen
import com.example.feature.chart.model.ChartDrawing
import com.example.feature.chart.model.DrawingTool
import com.example.feature.chart.model.FibTimeUnit
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class FibonacciSettingsScreenTest {
    @get:Rule val compose = createComposeRule()

    private val candles = (0 until 360).map { i ->
        Candle("XAUUSD", Timeframe.M5, 1_730_000_000_000L + i * 300_000L,
            open = 4200.0, high = 4210.0, low = 4160.0, close = 4190.0)
    }
    private val drawing = ChartDrawing(id = 73, tool = DrawingTool.FIBONACCI,
        symbol = "XAUUSD", timeframe = "M5", startPrice = 4204.64,
        endPrice = 4169.28, startTime = candles[304].openTime,
        endTime = candles[301].openTime)

    private fun capture(path: String) {
        compose.waitForIdle()
        val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        android.os.ParcelFileDescriptor.AutoCloseInputStream(
            automation.executeShellCommand("screencap -p /sdcard/Download/$path")
        ).use { it.readBytes() }
    }

    @Test fun threeTabsRenderOnNativeAndroidAndSaveTheEditedFibonacci() {
        var saved: ChartDrawing? = null
        compose.setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize()) {
                    FibonacciSettingsScreen(drawing, candles, onCancel = {},
                        onSave = { saved = it }, onDelete = {})
                }
            }
        }
        compose.onNodeWithTag("fib_title").assertTextEquals("تصحيح فيبوناتشي")
        compose.onNodeWithTag("fib_level_value_0").assertIsDisplayed()
        capture("tradelab-fibonacci-style.png")

        compose.onNodeWithTag("fib_level_enabled_1").performClick()
        compose.onNodeWithTag("fib_tab_1").performClick()
        compose.onNodeWithTag("fib_price_0").assertIsDisplayed()
        compose.onNodeWithTag("fib_confirm").assertIsDisplayed()
        compose.onNodeWithTag("fib_cancel").assertIsDisplayed()
        capture("tradelab-fibonacci-coordinates.png")
        compose.onNodeWithTag("fib_price_0").performTextReplacement("4199.00")

        compose.onNodeWithTag("fib_tab_2").performClick()
        compose.onNodeWithTag("fib_visible_MINUTES").assertIsDisplayed()
        compose.onNodeWithTag("fib_confirm").assertIsDisplayed()
        compose.onNodeWithTag("fib_cancel").assertIsDisplayed()
        capture("tradelab-fibonacci-visibility.png")
        compose.onNodeWithTag("fib_visible_MINUTES").performClick()
        compose.onNodeWithTag("fib_confirm").performClick()

        compose.runOnIdle {
            assertNotNull(saved)
            assertEquals(4199.0, saved!!.startPrice, .0001)
            assertTrue(saved!!.fibonacci.levels[1].enabled)
            assertFalse(saved!!.fibonacci.timeRules.first { it.unit == FibTimeUnit.MINUTES }.enabled)
            assertEquals(candles[304].openTime, saved!!.startTime)
        }
    }

    @Test fun cancelDoesNotPersistChanges() {
        var saved = false
        var canceled = false
        compose.setContent {
            MaterialTheme {
                FibonacciSettingsScreen(drawing, candles, onCancel = { canceled = true },
                    onSave = { saved = true }, onDelete = {})
            }
        }
        compose.onNodeWithTag("fib_level_enabled_0").performClick()
        compose.onNodeWithTag("fib_cancel").performClick()
        compose.runOnIdle { assertTrue(canceled); assertFalse(saved) }
    }
}
