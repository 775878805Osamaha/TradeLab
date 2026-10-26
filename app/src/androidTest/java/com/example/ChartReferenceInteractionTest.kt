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
            repeat(4) {
                compose.onNodeWithTag("candlestick_canvas").performTouchInput { swipeLeft(durationMillis = 500) }
                compose.onNodeWithTag("candlestick_canvas").performTouchInput { swipeRight(durationMillis = 500) }
            }
        } finally {
            compose.runOnIdle { compose.activity.window.removeOnFrameMetricsAvailableListener(listener) }
            thread.quitSafely()
            thread.join(2000)
            val samples = durations.filter { it > 0 }.sorted()
            val p95 = samples.getOrNull(((samples.size - 1) * .95).toInt().coerceAtLeast(0))?.div(1_000_000.0)
            val overBudget = samples.count { it > 16_666_667L }
            java.io.File(compose.activity.getExternalFilesDir(null), "chart-frame-metrics.json").writeText(
                """{"samples":${samples.size},"p95_frame_ms":$p95,"over_16_67ms":$overBudget,"environment":"GitHub Android emulator; software GPU; not a physical-device FPS guarantee"}"""
            )
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
