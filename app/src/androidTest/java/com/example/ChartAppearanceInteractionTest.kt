package com.example

import androidx.compose.ui.test.*
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
            compose.onNodeWithText(text(R.string.appearance_save)).performClick()
            compose.waitUntil(90000) { compose.onAllNodesWithTag("candlestick_canvas").fetchSemanticsNodes().isNotEmpty() }
            capture("appearance-light")
            compose.activityRule.scenario.recreate()
            compose.waitUntil(5000) { com.example.ui.theme.AppPalette.light }
            open()
            compose.onNodeWithText(text(R.string.appearance_dark)).performClick()
            compose.waitUntil(5000) { !com.example.ui.theme.AppPalette.light }
            compose.onNodeWithText(text(R.string.appearance_save)).performClick()
            capture("appearance-dark")
            assertEquals("dark", compose.activity.getSharedPreferences("appearance",0).getString("mode",null))
        } finally {
            compose.activity.getSharedPreferences("appearance",0).edit().putString("mode","dark").commit()
        }
    }
}
