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
            wicks = false, hollow = true, background = -1, line = 0xFF654321.toInt(),
            gridColor = 0xFF808080.toInt(), lastPrice = false, sourceTime = false, axisScale = 1.3f)
        custom.save(prefs)
        assertEquals(custom, ChartAppearance.load(context.getSharedPreferences("appearance_test", 0)))
        ChartAppearance().save(prefs)
        assertEquals(ChartAppearance(), ChartAppearance.load(prefs))
        assertFalse(prefs.contains("background"))
        assertFalse(prefs.contains("grid_color"))
    }
    @Test fun invalidAxisScaleCannotReachCanvas() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = context.getSharedPreferences("appearance_scale_test",0)
        prefs.edit().clear().putFloat("axis_scale", Float.NaN).commit()
        assertEquals(1f, ChartAppearance.load(prefs).axisScale, 0f)
        ChartAppearance(axisScale = Float.POSITIVE_INFINITY).save(prefs)
        assertEquals(1f, ChartAppearance.load(prefs).axisScale, 0f)
        ChartAppearance(axisScale = 100f).save(prefs)
        assertEquals(1.4f, ChartAppearance.load(prefs).axisScale, 0f)
    }
}
