package com.example.feature.chart

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.feature.chart.model.IndicatorSettings
import com.example.core.model.Tick
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
class ChartWorkspaceSettingsTest {
    @Test fun settingsAndTemplateAreIndependentAndSurviveNewPreferenceRead() {
        val context=ApplicationProvider.getApplicationContext<Context>()
        val prefs=context.getSharedPreferences("workspace_test",0)
        prefs.edit().clear().commit()
        val settings=IndicatorSettings(smaPeriod=53,isSmaEnabled=true,emaPeriod=34,rsiPeriod=9,
            macdFast=8,macdSlow=21,macdSignal=5,isMacdEnabled=true,bollingerStdDev=2.5)
        ChartWorkspaceSettings.save(prefs,"indicators",settings)
        ChartWorkspaceSettings.save(prefs,"indicator_template",settings.copy(smaPeriod=100))
        assertEquals(settings,ChartWorkspaceSettings.load(context.getSharedPreferences("workspace_test",0)))
        assertEquals(100,ChartWorkspaceSettings.load(prefs,"indicator_template").smaPeriod)
    }
    @Test fun corruptUnsupportedAndUnsafeSettingsFallBack() {
        for(raw in listOf(null,"","2|20,20,20,14,12,26,9,14|2.0|false,true,false,false,false,false,false",
            "1|20,20,20,14,26,12,9,14|2.0|false,true,false,false,false,false,false",
            "1|20,20,20,14,12,26,9,14|NaN|false,true,false,false,false,false,false")) {
            assertEquals(IndicatorSettings(isEmaEnabled=false),ChartWorkspaceSettings.decode(raw))
        }
    }
    @Test fun alertsUseVerifiedFreshBidAndInclusiveThreshold() {
        val now=1_800_000_000_000L
        val tick=Tick("XAUUSD",2000.0,2001.0,timestamp=now,source="BIQUOTE_REST")
        assertTrue(ChartPriceAlertRule.reached(tick,"XAUUSD",2000.0,true,false,now))
        assertTrue(ChartPriceAlertRule.reached(tick,"XAUUSD",2000.0,false,false,now))
        assertFalse(ChartPriceAlertRule.reached(tick,"XAUUSD",2000.5,true,false,now))
        assertFalse(ChartPriceAlertRule.reached(tick,"XAUUSD",1999.0,false,false,now))
    }
    @Test fun alertsRejectReplayStaleWrongSymbolAndUnverifiedQuotes() {
        val now=1_800_000_000_000L
        val tick=Tick("XAUUSD",2000.0,2001.0,timestamp=now,source="BIQUOTE_REST")
        assertFalse(ChartPriceAlertRule.reached(tick,"XAUUSD",1999.0,true,true,now))
        assertFalse(ChartPriceAlertRule.reached(tick,"XAUUSD",1999.0,true,false,now+16000))
        assertFalse(ChartPriceAlertRule.reached(tick,"EURUSD",1.0,true,false,now))
        assertFalse(ChartPriceAlertRule.reached(tick.copy(source="TEST_FIXTURE"),"XAUUSD",1999.0,true,false,now))
        assertFalse(ChartPriceAlertRule.reached(tick,"XAUUSD",Double.NaN,true,false,now))
    }
}
