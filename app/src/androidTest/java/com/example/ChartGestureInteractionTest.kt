package com.example

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.ui.components.CandlestickChart
import com.example.ui.components.ChartCandleWidthPx
import com.example.ui.components.ChartFirstVisibleIndex
import com.example.ui.components.ChartPriceIndexReady
import com.example.ui.components.ChartScrollOffsetPx
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises actual Android pointer dispatch, not just pure zoom formulas. */
@RunWith(AndroidJUnit4::class)
class ChartGestureInteractionTest {
    @get:Rule val compose = createComposeRule()

    private val candles = List(2_000) { i ->
        val base = 2_300.0 + i * .025 + kotlin.math.sin(i * .1) * 4.0
        val time = 1_730_000_000_000L + i * 60_000L
        Candle("XAUUSD", Timeframe.M1, time, open = base - 1.0, high = base + 3.0,
            low = base - 3.0, close = base + 1.0, volume = 100.0,
            closeTime = time + 60_000L, source = "GESTURE_TEST_FIXTURE")
    }

    @Test fun oneFingerPanAndTwoFingerZoomRemainResponsive() {
        compose.setContent {
            MaterialTheme { CandlestickChart(candles, Modifier.fillMaxSize(), referenceLayout = true) }
        }
        fun node() = compose.onNodeWithTag("candlestick_canvas").fetchSemanticsNode()
        compose.waitUntil(15_000) { node().config[ChartPriceIndexReady] }

        val before = node().config[ChartFirstVisibleIndex]
        compose.onNodeWithTag("candlestick_canvas").performTouchInput {
            swipeRight(durationMillis = 600)
        }
        compose.waitForIdle()
        assertTrue("Dragging right must expose older market bars",
            node().config[ChartFirstVisibleIndex] < before)

        val widthBefore = node().config[ChartCandleWidthPx]
        val bounds = node().boundsInRoot
        val center = Offset(bounds.width * .5f, bounds.height * .47f)
        compose.onNodeWithTag("candlestick_canvas").performTouchInput {
            pinch(
                start0 = center - Offset(55f, 0f),
                start1 = center + Offset(55f, 0f),
                end0 = center - Offset(130f, 0f),
                end1 = center + Offset(130f, 0f),
                durationMillis = 600
            )
        }
        compose.waitForIdle()
        val widthAfterZoomIn = node().config[ChartCandleWidthPx]
        assertTrue("Pinch-out must enlarge candles", widthAfterZoomIn > widthBefore * 1.25f)

        val ui = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val screenshot = ui.executeShellCommand(
            "screencap -p /sdcard/Download/tradelab-chart-gesture-zoom.png"
        )
        android.os.ParcelFileDescriptor.AutoCloseInputStream(screenshot).use { it.readBytes() }

        compose.onNodeWithTag("candlestick_canvas").performTouchInput {
            pinch(
                start0 = center - Offset(130f, 0f),
                start1 = center + Offset(130f, 0f),
                end0 = center - Offset(55f, 0f),
                end1 = center + Offset(55f, 0f),
                durationMillis = 600
            )
        }
        compose.waitForIdle()
        assertTrue("Pinch-in must shrink candles",
            node().config[ChartCandleWidthPx] < widthAfterZoomIn)
    }

    @Test fun fastFlickContinuesBrieflyAfterRelease() {
        compose.setContent {
            MaterialTheme { CandlestickChart(candles, Modifier.fillMaxSize()) }
        }
        fun node() = compose.onNodeWithTag("candlestick_canvas").fetchSemanticsNode()
        compose.waitUntil(15_000) { node().config[ChartPriceIndexReady] }
        val startOffset = node().config[ChartScrollOffsetPx]
        val chartWidth = node().boundsInRoot.width
        compose.onNodeWithTag("candlestick_canvas").performTouchInput {
            swipeRight(durationMillis = 110)
        }
        compose.waitForIdle()
        val finalOffset = node().config[ChartScrollOffsetPx]
        assertTrue("A quick flick should glide farther than the injected finger travel",
            finalOffset - startOffset > chartWidth * .85f)
    }
}
