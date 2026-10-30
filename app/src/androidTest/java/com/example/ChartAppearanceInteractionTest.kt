package com.example

import androidx.compose.ui.test.*
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*

@RunWith(AndroidJUnit4::class)
class ChartAppearanceInteractionTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    private fun capture(name: String) {
        compose.waitForIdle()
        val ui = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val descriptor = ui.executeShellCommand("screencap -p /sdcard/Download/$name.png")
        android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { it.readBytes() }
    }

    @Test fun colorsAndThemeSurviveActivityRecreation() {
        val resources = compose.activity.resources
        fun text(id: Int) = resources.getString(id)
        fun open() {
            compose.onNodeWithContentDescription("المزيد").performClick()
            compose.onNodeWithText(text(R.string.chart_appearance)).performClick()
        }
        try {
            open()
            compose.onNodeWithText(text(R.string.appearance_light)).performClick()
            compose.waitUntil(5000) { com.example.ui.theme.AppPalette.light }
            compose.onAllNodes(hasSetTextAction()).onFirst().performScrollTo().performTextReplacement("-12345")
            compose.onAllNodesWithText(text(R.string.appearance_apply)).onFirst().assertIsNotEnabled()
            compose.onAllNodes(hasSetTextAction()).onFirst().performTextReplacement("112233")
            compose.onAllNodesWithText(text(R.string.appearance_apply)).onFirst().performClick()
            androidx.test.espresso.Espresso.closeSoftKeyboard()
            compose.onNodeWithText(text(R.string.appearance_save)).performClick()
            compose.waitForIdle()
            assertTrue(compose.onNodeWithTag("bottom_nav_bar").captureToImage().toPixelMap()[0,0].luminance() > .7f)
            compose.waitUntil(90000) { compose.onAllNodesWithTag("candlestick_canvas").fetchSemanticsNodes().isNotEmpty() }
            capture("appearance-light")
            for ((route, screen) in listOf("market" to "market_screen", "results" to "results_screen", "account" to "account_screen")) {
                compose.onNodeWithTag("nav_item_$route").performClick()
                compose.onNodeWithTag(screen).assertIsDisplayed()
                compose.waitForIdle()
                assertTrue(compose.onNodeWithTag(screen).captureToImage().toPixelMap()[0,0].luminance() > .7f)
                capture("appearance-light-$route")
            }
            compose.onNodeWithTag("account_settings").performClick()
            compose.onNodeWithTag("settings_screen").assertIsDisplayed()
            compose.onNodeWithText(text(R.string.appearance_title)).assertIsDisplayed()
            androidx.test.espresso.Espresso.pressBack()
            compose.waitUntil(5000) {
                compose.onAllNodesWithTag("account_screen").fetchSemanticsNodes().isNotEmpty() &&
                    compose.onAllNodesWithTag("settings_screen").fetchSemanticsNodes().isEmpty() &&
                    compose.onAllNodesWithTag("nav_item_chart").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("settings_screen").assertDoesNotExist()
            compose.onNodeWithTag("nav_item_chart").performClick()
            compose.activityRule.scenario.recreate()
            compose.waitUntil(5000) { com.example.ui.theme.AppPalette.light }
            assertEquals(0xFF112233.toInt(), compose.activity.getSharedPreferences("chart_appearance",0).getInt("up",0))
            open()
            compose.onAllNodes(hasSetTextAction()).onFirst().assertTextContains("112233")
            compose.onNodeWithText(text(R.string.appearance_dark)).performClick()
            compose.waitUntil(5000) { !com.example.ui.theme.AppPalette.light }
            compose.onNodeWithText(text(R.string.appearance_save)).performClick()
            compose.waitForIdle()
            assertTrue(compose.onNodeWithTag("bottom_nav_bar").captureToImage().toPixelMap()[0,0].luminance() < .1f)
            capture("appearance-dark")
            assertEquals("dark", compose.activity.getSharedPreferences("appearance",0).getString("mode",null))
        } finally {
            compose.activity.getSharedPreferences("appearance",0).edit().putString("mode","dark").commit()
            compose.activity.getSharedPreferences("chart_appearance",0).edit().clear().commit()
        }
    }
}
