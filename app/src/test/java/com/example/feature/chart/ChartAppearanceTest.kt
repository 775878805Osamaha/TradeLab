package com.example.feature.chart

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ChartAppearanceTest {
    @Test fun appearanceSurvivesReloadAndResetRemovesCustomBackground() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = context.getSharedPreferences("appearance_test", 0)
        prefs.edit().clear().commit()
        assertEquals(ChartAppearance(), ChartAppearance.load(prefs))
        val custom = ChartAppearance(up = 0xFF123456.toInt(), down = 0xFFABCDEF.toInt(), grid = false,
            wicks = false, hollow = true, background = -1)
        custom.save(prefs)
        assertEquals(custom, ChartAppearance.load(context.getSharedPreferences("appearance_test", 0)))
        ChartAppearance().save(prefs)
        assertEquals(ChartAppearance(), ChartAppearance.load(prefs))
        assertFalse(prefs.contains("background"))
    }
}
