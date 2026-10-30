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
            compose.activityRule.scenario.recreate()
            compose.waitUntil(5000) { com.example.ui.theme.AppPalette.light }
            open()
            compose.onNodeWithText(text(R.string.appearance_dark)).performClick()
            compose.waitUntil(5000) { !com.example.ui.theme.AppPalette.light }
            compose.onNodeWithText(text(R.string.appearance_save)).performClick()
            assertEquals("dark", compose.activity.getSharedPreferences("appearance",0).getString("mode",null))
        } finally {
            compose.activity.getSharedPreferences("appearance",0).edit().putString("mode","dark").commit()
        }
    }
}
