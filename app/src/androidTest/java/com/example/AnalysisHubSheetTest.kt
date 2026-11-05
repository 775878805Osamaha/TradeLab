package com.example

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.feature.chart.AnalysisHubCatalog
import com.example.feature.chart.AnalysisHubSheet
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class AnalysisHubSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun referenceCategoriesAndPrimaryActionsAreClickable() {
        assertEquals(listOf("indicators", "compare", "alerts", "bar_replay"),
            AnalysisHubCatalog.toolsWide.map { it.id })
        assertEquals(listOf("indicator_templates", "chart_type", "object_tree"),
            AnalysisHubCatalog.toolsCompact.map { it.id })
        val actions = mutableListOf<String>()
        compose.setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize().background(Color.White)) {
                    AnalysisHubSheet(onDismiss = {}, onAction = { actions += it })
                }
            }
        }
        compose.waitUntil(7_000) {
            runCatching { compose.onNodeWithTag("analysis_hub_title").assertIsDisplayed() }.isSuccess
        }
        compose.onNodeWithTag("analysis_hub_title").assertTextEquals("محور التحليل")
        compose.onNodeWithTag("analysis_hub_chart_type").performClick()
        compose.runOnIdle { assertEquals(listOf("chart_type"), actions) }
        compose.onNodeWithTag("analysis_hub_financial_data").assertIsNotEnabled()
        compose.onNodeWithTag("analysis_hub_forecasts").assertIsNotEnabled()
    }

    @Test fun screenshotArabicAnalysisHubOnRealAndroid() {
        compose.setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize().background(Color.White)) {
                    AnalysisHubSheet(onDismiss = {}, onAction = {})
                }
            }
        }
        compose.waitUntil(7_000) {
            runCatching { compose.onNodeWithTag("analysis_hub_title").assertIsDisplayed() }.isSuccess
        }
        compose.waitForIdle()
        Thread.sleep(900)
        val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        val bitmap = requireNotNull(automation.takeScreenshot())
        var darkPixels = 0
        for (y in bitmap.height / 7 until bitmap.height * 6 / 7 step 16) {
            for (x in bitmap.width / 8 until bitmap.width * 7 / 8 step 16) {
                val c = bitmap.getPixel(x, y)
                if (android.graphics.Color.red(c) < 110 &&
                    android.graphics.Color.green(c) < 110 &&
                    android.graphics.Color.blue(c) < 110
                ) darkPixels++
            }
        }
        assertTrue("Analysis hub title, labels and icons must be captured", darkPixels > 30)
        android.os.ParcelFileDescriptor.AutoCloseInputStream(
            automation.executeShellCommand("screencap -p /sdcard/Download/tradelab-analysis-hub.png")
        ).use { it.readBytes() }
    }
}
