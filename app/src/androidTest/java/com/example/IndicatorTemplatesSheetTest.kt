package com.example

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.feature.chart.IndicatorTemplates
import com.example.feature.chart.IndicatorTemplatesSheet
import com.example.feature.chart.model.IndicatorSettings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class IndicatorTemplatesSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun presetsChangeOnlyIndicatorVisibilityAndHaveWorkingActions() {
        val initial = IndicatorSettings(emaPeriod = 34, rsiPeriod = 9)
        var applied: IndicatorSettings? = null
        var saved = false
        compose.setContent {
            MaterialTheme {
                IndicatorTemplatesSheet(initial, null,
                    onApply = { applied = it }, onSaveCurrent = { saved = true }, onDismiss = {})
            }
        }
        compose.waitForIdle()
        val automation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
        android.os.ParcelFileDescriptor.AutoCloseInputStream(
            automation.executeShellCommand("screencap -p /sdcard/Download/tradelab-indicator-templates.png")
        ).use { it.readBytes() }
        compose.onNodeWithTag("indicator_template_trend").performClick()
        compose.runOnIdle {
            assertEquals(34, applied?.emaPeriod)
            assertEquals(9, applied?.rsiPeriod)
            assertTrue(applied!!.isEmaEnabled)
            assertTrue(applied!!.isSmaEnabled)
            assertTrue(applied!!.isVwapEnabled)
            assertFalse(applied!!.isMacdEnabled)
        }
        compose.onNodeWithTag("indicator_template_save").performClick()
        compose.runOnIdle { assertTrue(saved) }
    }

    @Test fun savedTemplateCanBeApplied() {
        val stored = IndicatorTemplates.momentum(IndicatorSettings(emaPeriod = 55))
        var applied: IndicatorSettings? = null
        compose.setContent {
            MaterialTheme {
                IndicatorTemplatesSheet(IndicatorSettings(), stored, { applied = it }, {}, {})
            }
        }
        compose.onNodeWithTag("indicator_template_saved").performClick()
        compose.runOnIdle { assertEquals(stored, applied) }
    }
}
