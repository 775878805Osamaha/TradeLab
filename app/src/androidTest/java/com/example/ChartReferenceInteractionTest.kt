package com.example

import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
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

    private fun captureProviderScreen(name: String) {
        compose.waitForIdle()
        val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        val descriptor = instrumentation.uiAutomation.executeShellCommand("screencap -p /sdcard/Download/$name.png")
        android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { it.readBytes() }
    }

    @Test fun threeMinuteGoldHistoryLoadsRealCandles() {
        compose.onNodeWithTag("chart_bottom_timeframe").performClick()
        compose.onNodeWithText("3m").performClick()
        compose.waitUntil(90000) {
            compose.onAllNodesWithTag("candlestick_canvas").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("chart_load_error").assertDoesNotExist()
        compose.onNodeWithTag("chart_bottom_timeframe").assertTextContains("3 دق", substring = true)
        captureProviderScreen("tradelab-gold-3m")
    }

    @Test fun legacyGoldTradeShowsVerifiedBidAskAndHistory() {
        // Live-quote acceptance is exercised on weekdays; closed markets must remain blocked.
        org.junit.Assume.assumeTrue(java.time.LocalDate.now(java.time.ZoneOffset.UTC).dayOfWeek.value <= 5)
        compose.onNodeWithTag("nav_item_account").performClick()
        compose.waitUntil(30000) {
            compose.onAllNodesWithTag("dash_action_trade").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("dash_action_trade").performScrollTo().performClick()
        compose.onNodeWithTag("trade_symbol_selector").performClick()
        compose.onAllNodesWithText("XAUUSD").onLast().performClick()
        compose.waitUntil(90000) {
            val node = compose.onAllNodesWithTag("trade_quote_bid").fetchSemanticsNodes().firstOrNull()
            val text = node?.config?.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.Text)
                ?.joinToString("") { it.text }?.replace(",", "")
            (text?.toDoubleOrNull() ?: 0.0) > 0.0
        }
        val app = compose.activity.application as TradeLabApplication
        val tick = kotlinx.coroutines.runBlocking { app.marketDataRepository.provider.getLatestTick("XAUUSD") }
        org.junit.Assert.assertTrue(com.example.core.market.VerifiedMarketQuote.isVerified(tick, "XAUUSD"))
        compose.onNodeWithTag("trade_quote_ask").assertIsDisplayed()
        compose.onNodeWithTag("trade_chart_card").performScrollTo()
        compose.waitUntil(90000) {
            compose.onAllNodesWithTag("candlestick_canvas").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("trade_quote_bid").performScrollTo()
        captureProviderScreen("tradelab-gold-trade")
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
        compose.onNodeWithTag("nav_item_chart").assertIsSelected()
        compose.onNodeWithTag("chart_bottom_symbol").assertIsDisplayed()
        androidx.test.espresso.Espresso.pressBack()
        compose.onNodeWithTag("chart_embedded_replay_controls").assertDoesNotExist()
        compose.onNodeWithTag("chart_bottom_strip").assertIsDisplayed()
    }
    @Test fun replayPositionLineOpensActionsAndPartialCloseKeepsChart() {
        // The production Replay account starts at $50. Use an affordable real
        // forex order so this interaction test also respects its margin checks.
        compose.onNodeWithTag("chart_bottom_symbol").performClick()
        compose.onNodeWithTag("chart_symbol_search").performTextInput("GBPUSD")
        compose.onNodeWithTag("chart_symbol_option_GBPUSD").performClick()
        compose.onNodeWithTag("chart_bottom_replay").performClick()
        compose.waitUntil(90000) {
            compose.onAllNodesWithTag("chart_replay_buy").fetchSemanticsNodes().firstOrNull()
                ?.config?.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.Disabled) == null &&
            compose.onAllNodesWithTag("candlestick_canvas").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("chart_replay_buy").performClick()
        compose.onNodeWithTag("chart_order_volume").performTextReplacement("0.02")
        androidx.test.espresso.Espresso.closeSoftKeyboard()
        compose.onNodeWithTag("chart_order_confirm").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("chart_replay_open_positions_summary").assertExists()
        // Entry is mapped by the real chart transform. Tap through the visible price
        // range without depending on a particular historical Gold price or date.
        for (step in 1..40) {
            if (compose.onAllNodesWithTag("chart_position_actions").fetchSemanticsNodes().isNotEmpty()) break
            compose.onNodeWithTag("candlestick_canvas").performTouchInput {
                click(androidx.compose.ui.geometry.Offset(width * .65f, height * step / 42f))
            }
        }
        compose.onNodeWithTag("chart_position_actions").assertIsDisplayed()
        captureProviderScreen("tradelab-position-actions")
        compose.onNodeWithTag("position_partial").performClick()
        compose.onNodeWithTag("position_action_value").performTextInput("0.01")
        androidx.test.espresso.Espresso.closeSoftKeyboard()
        compose.onNodeWithTag("position_action_confirm").performClick()
        compose.onNodeWithTag("chart_replay_open_positions_summary").assertExists()
        compose.onNodeWithTag("nav_item_chart").assertIsSelected()
        captureProviderScreen("tradelab-compact-replay")
        for (step in 1..40) {
            if (compose.onAllNodesWithTag("chart_position_actions").fetchSemanticsNodes().isNotEmpty()) break
            compose.onNodeWithTag("candlestick_canvas").performTouchInput {
                click(androidx.compose.ui.geometry.Offset(width * .65f, height * step / 42f))
            }
        }
        compose.onNodeWithText("الحجم المفتوح: 0.01 لوت").assertIsDisplayed()
    }

    private fun shell(command: String) {
        val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        android.os.ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand(command)).use { it.readBytes() }
    }

    @Test fun drawingCatalogMatchesReferenceAndPersistsMultiPointGeometry() {
        val app = compose.activity.application as TradeLabApplication
        val dao = app.database.drawingDao()
        kotlinx.coroutines.runBlocking { dao.clearDrawings("XAUUSD", "M15") }
        try {
            // Match the supplied 691px-wide reference; leave other chart tests at their established viewport.
            shell("wm size 691x1536")
            shell("wm density 276")
            compose.waitUntil(30000) { compose.onAllNodesWithTag("chart_bottom_strip").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithContentDescription("أدوات الرسم").performClick()
            compose.onNodeWithTag("drawing_catalog_sheet").assertExists()
            compose.onNodeWithTag("drawing_sheet_handle").performTouchInput {
                swipe(center, center - androidx.compose.ui.geometry.Offset(0f, 600f), 500)
            }
            captureProviderScreen("drawing-catalog-favorites")
            for ((category, name) in listOf("الأشكال الهندسية" to "shapes", "ملاحظة" to "notes", "نماذج" to "patterns", "التنبؤ والقياس" to "measurement")) {
                compose.onNodeWithTag("drawing_category_$category").performScrollTo().performClick()
                captureProviderScreen("drawing-catalog-$name")
            }
            compose.onNodeWithTag("drawing_favorites_switch").performClick()
            androidx.test.espresso.Espresso.pressBack()
            compose.onNodeWithTag("chart_favorite_TRENDLINE").assertExists()
            compose.onNodeWithContentDescription("أدوات الرسم").performClick()
            compose.onNodeWithTag("drawing_favorites_switch").performClick()
            compose.onNodeWithTag("drawing_catalog_search").performTextInput("مثلث")
            compose.onNodeWithTag("drawing_tool_TRIANGLE").performClick()
            compose.waitUntil(90000) { compose.onAllNodesWithTag("candlestick_canvas").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("candlestick_canvas").performTouchInput {
                click(androidx.compose.ui.geometry.Offset(width*.55f,height*.45f))
                click(androidx.compose.ui.geometry.Offset(width*.75f,height*.55f))
                click(androidx.compose.ui.geometry.Offset(width*.6f,height*.7f))
            }
            compose.waitUntil(10000) {
                kotlinx.coroutines.runBlocking { dao.getDrawings("XAUUSD","M15").first().any { it.type == "TRIANGLE" } }
            }
            val stored = kotlinx.coroutines.runBlocking { dao.getDrawings("XAUUSD","M15").first().first { it.type == "TRIANGLE" } }
            org.junit.Assert.assertEquals(3, com.example.feature.chart.model.ChartDrawing.fromEntity(stored)!!.anchors.size)
            captureProviderScreen("drawing-catalog-triangle")
            compose.onNodeWithTag("candlestick_canvas").performTouchInput {
                longClick(androidx.compose.ui.geometry.Offset(width*.55f,height*.45f))
            }
            compose.onNodeWithTag("drawing_properties").assertIsDisplayed()
            androidx.test.espresso.Espresso.pressBack()
        } finally {
            shell("wm size 864x1536")
            shell("wm density 346")
            kotlinx.coroutines.runBlocking { dao.clearDrawings("XAUUSD", "M15") }
        }
    }

}
