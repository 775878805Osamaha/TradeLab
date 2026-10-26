package com.example

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises the production Activity and its existing NavHost, not a mock screen. */
@RunWith(AndroidJUnit4::class)
class ChartReferenceInteractionTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun fourDestinationsNavigateAndRestoreChartControls() {
        compose.onNodeWithTag("chart_bottom_strip").assertIsDisplayed()
        compose.onNodeWithTag("chart_reference_tool_0").assertIsDisplayed()
        compose.onNodeWithTag("chart_reference_tool_8").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("nav_item_chart").assertIsSelected()
        for ((route, screen) in listOf("market" to "market_screen", "results" to "results_screen", "account" to "account_screen")) {
            compose.onNodeWithTag("nav_item_$route").performClick()
            compose.onNodeWithTag("nav_item_$route").assertIsSelected()
            compose.onNodeWithTag(screen).assertIsDisplayed()
        }
        compose.onNodeWithTag("nav_item_chart").performClick()
        compose.onNodeWithTag("chart_bottom_symbol").assertIsDisplayed()
        compose.onNodeWithTag("chart_bottom_timeframe").assertIsDisplayed()
        compose.onNodeWithTag("chart_bottom_replay").assertIsDisplayed()
        compose.onNodeWithTag("nav_item_trade").assertDoesNotExist()
        compose.onNodeWithTag("chart_floating_symbol_selector").assertDoesNotExist()
        compose.onNodeWithTag("chart_floating_timeframe").assertDoesNotExist()
    }

    @Test fun recordActualPanFrameDurations() {
        val durations = java.util.concurrent.CopyOnWriteArrayList<Long>()
        val thread = android.os.HandlerThread("chart-frame-measurement").apply { start() }
        val listener = android.view.Window.OnFrameMetricsAvailableListener { _, metrics, _ ->
            durations.add(metrics.getMetric(android.view.FrameMetrics.TOTAL_DURATION))
        }
        compose.runOnIdle {
            compose.activity.window.addOnFrameMetricsAvailableListener(listener, android.os.Handler(thread.looper))
        }
        try {
            compose.waitUntil(30000) {
                compose.onAllNodesWithTag("candlestick_canvas").fetchSemanticsNodes().isNotEmpty()
            }
            val bounds = compose.onNodeWithTag("candlestick_canvas").fetchSemanticsNode().boundsInRoot
            val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
            val y = bounds.top + bounds.height * .45f
            fun drag(from: Float, to: Float) {
                val downTime = android.os.SystemClock.uptimeMillis()
                fun send(action: Int, x: Float) {
                    val event = android.view.MotionEvent.obtain(downTime, android.os.SystemClock.uptimeMillis(), action, x, y, 0)
                    event.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
                    try { org.junit.Assert.assertTrue(automation.injectInputEvent(event, true)) }
                    finally { event.recycle() }
                }
                send(android.view.MotionEvent.ACTION_DOWN, from)
                for (step in 1..24) {
                    android.os.SystemClock.sleep(16)
                    send(android.view.MotionEvent.ACTION_MOVE, from + (to - from) * step / 24f)
                }
                send(android.view.MotionEvent.ACTION_UP, to)
                compose.waitForIdle()
            }
            durations.clear()
            repeat(4) {
                // Both endpoints stay in the candle plot, clear of the price axis and tool rail.
                drag(bounds.left + bounds.width * .70f, bounds.left + bounds.width * .30f)
                drag(bounds.left + bounds.width * .30f, bounds.left + bounds.width * .70f)
            }
        } finally {
            compose.runOnIdle { compose.activity.window.removeOnFrameMetricsAvailableListener(listener) }
            thread.quitSafely()
            thread.join(2000)
            val samples = durations.filter { it > 0 }.sorted()
            val p95 = samples.getOrNull(((samples.size - 1) * .95).toInt().coerceAtLeast(0))?.div(1_000_000.0)
            val overBudget = samples.count { it > 16_666_667L }
            val result = """{"samples":${samples.size},"p95_frame_ms":$p95,"over_16_67ms":$overBudget,"environment":"GitHub Android emulator; software GPU; not a physical-device FPS guarantee"}"""
            // UTP retains per-test logcat even when it uninstalls the target APK.
            android.util.Log.i("TradeLabFrameMetrics", result)
        }
    }

    @Test fun bottomSelectorsOpenActualMenus() {
        compose.onNodeWithTag("chart_bottom_symbol").performClick()
        compose.onNodeWithTag("chart_symbol_search").assertIsDisplayed()
        androidx.test.espresso.Espresso.pressBack()
        compose.onNodeWithTag("chart_bottom_timeframe").performClick()
        compose.onNodeWithText("3m").assertIsDisplayed()
        compose.onNodeWithText("2h").assertIsDisplayed()
        compose.onNodeWithText("1W").assertIsDisplayed()
        compose.onNodeWithText("2h").performClick()
        compose.onNodeWithTag("chart_bottom_timeframe").assertIsDisplayed()
    }

    @Test fun compactReplayUsesEmbeddedControlsAndCloses() {
        compose.onNodeWithTag("chart_bottom_replay").performClick()
        compose.onNodeWithTag("chart_embedded_replay_controls").assertIsDisplayed()
        compose.onNodeWithTag("chart_replay_close").performClick()
        compose.onNodeWithTag("chart_embedded_replay_controls").assertDoesNotExist()
        compose.onNodeWithTag("chart_bottom_strip").assertIsDisplayed()
    }
}
