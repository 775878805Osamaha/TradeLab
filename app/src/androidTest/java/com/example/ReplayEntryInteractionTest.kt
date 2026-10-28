package com.example

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Checks mode transitions in the production Activity and NavHost. */
@RunWith(AndroidJUnit4::class)
class ReplayEntryInteractionTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    private fun assertAnalysis() {
        compose.onNodeWithTag("chart_bottom_strip").assertIsDisplayed()
        compose.onNodeWithTag("chart_embedded_replay_controls").assertDoesNotExist()
        compose.onNodeWithTag("chart_replay_trading_bar").assertDoesNotExist()
    }

    @Test fun chartStartsInAnalysisAndStaysThereAfterRecreation() {
        assertAnalysis()
        compose.activityRule.scenario.recreate()
        assertAnalysis()
    }

    @Test fun replayIconTogglesControlsAndCloseReturnsToAnalysis() {
        assertAnalysis()
        compose.onNodeWithTag("chart_bottom_replay").performClick()
        compose.onNodeWithTag("chart_embedded_replay_controls").assertIsDisplayed()
        compose.onNodeWithTag("chart_bottom_replay").performClick()
        assertAnalysis()
        compose.onNodeWithTag("chart_bottom_replay").performClick()
        compose.onNodeWithTag("chart_replay_close").performClick()
        assertAnalysis()
    }

    @Test fun backExitsPausedReplayWithoutLeavingChart() {
        compose.onNodeWithTag("chart_bottom_replay").performClick()
        compose.onNodeWithTag("chart_embedded_replay_controls").assertIsDisplayed()
        Espresso.pressBack()
        assertAnalysis()
        compose.onNodeWithTag("nav_item_chart").assertIsSelected()
    }

    @Test fun analysisSymbolAndTimeframeChangesDoNotEnterReplay() {
        compose.onNodeWithTag("chart_bottom_symbol").performClick()
        compose.onNodeWithTag("chart_symbol_search").performTextInput("BTCUSDT")
        compose.onNodeWithTag("chart_symbol_option_BTCUSDT").performClick()
        compose.onNodeWithTag("chart_bottom_timeframe").performClick()
        compose.onNodeWithText("2h").performClick()
        assertAnalysis()
        compose.onNodeWithTag("chart_bottom_symbol").assertTextContains("BTCUSDT", substring = true)
        compose.onNodeWithTag("chart_bottom_timeframe").assertTextContains("2 س", substring = true)
    }

    @Test fun consumedTrainingRequestDoesNotReopenReplayOnTabReturn() {
        compose.onNodeWithTag("nav_item_account").performClick()
        compose.waitUntil(90000) {
            compose.onAllNodes(hasTestTag("training_start") and isEnabled())
                .fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("training_start").performScrollTo().performClick()
        compose.onNodeWithTag("chart_embedded_replay_controls").assertIsDisplayed()
        compose.onNodeWithTag("chart_replay_close").performClick()
        assertAnalysis()
        compose.onNodeWithTag("nav_item_account").performClick()
        compose.onNodeWithTag("nav_item_chart").performClick()
        assertAnalysis()
        compose.activityRule.scenario.recreate()
        assertAnalysis()
    }
}
