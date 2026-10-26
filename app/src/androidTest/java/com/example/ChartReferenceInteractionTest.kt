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
