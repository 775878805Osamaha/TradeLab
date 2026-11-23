package com.example

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises entry points in the installed app, without fabricated market candles. */
@RunWith(AndroidJUnit4::class)
class TradingLabNavigationTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun laboratoryAndHistoricalBacktestAreReachableFromBottomBar() {
        compose.onNodeWithTag("nav_item_trade").assertIsDisplayed().performClick()
        compose.onNodeWithTag("lab_screen").assertIsDisplayed()
        compose.onNodeWithTag("nav_item_trade").assertIsSelected()

        compose.onNodeWithTag("lab_start_backtest").performScrollTo().performClick()
        compose.onNodeWithTag("backtest_screen").assertIsDisplayed()
        compose.onNodeWithText("الإعدادات").assertIsDisplayed()

        Espresso.pressBack()
        compose.onNodeWithTag("lab_screen").assertIsDisplayed()
        compose.onNodeWithTag("lab_open_strategies").performScrollTo().performClick()
        compose.onNodeWithTag("strategy_screen").assertIsDisplayed()
    }

    @Test fun manualSimulatorOpensReplayOnTheSameChart() {
        compose.onNodeWithTag("nav_item_trade").performClick()
        compose.onNodeWithTag("lab_start_simulator").performClick()
        compose.onNodeWithTag("nav_item_chart").assertIsSelected()
        compose.onNodeWithTag("chart_embedded_replay_controls").assertIsDisplayed()
    }
}
