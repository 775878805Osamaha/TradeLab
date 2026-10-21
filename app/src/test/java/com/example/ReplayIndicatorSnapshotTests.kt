package com.example

import com.example.core.model.Candle
import com.example.feature.chart.model.IndicatorSettings
import com.example.feature.replay.ReplayIndicatorSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReplayIndicatorSnapshotTests {
    private fun candle(index: Int): Candle =
        Candle(openTime = index * 60_000L, open = 100.0 + index,
            high = 101.0 + index, low = 99.0 + index,
            close = 100.5 + index, volume = 10.0)

    @Test fun disabledIndicatorsDoNotAllocateSeries() {
        val result = ReplayIndicatorSnapshot.calculate(
            (0..30).map(::candle),
            IndicatorSettings(isEmaEnabled = false)
        )
        assertTrue(result.sma.isEmpty())
        assertTrue(result.ema.isEmpty())
        assertTrue(result.bollinger.isEmpty())
        assertTrue(result.vwap.isEmpty())
        assertTrue(result.rsi.isEmpty())
        assertTrue(result.macd.isEmpty())
        assertTrue(result.atr.isEmpty())
    }

    @Test fun enabledSeriesAreBoundedToRevealedCandles() {
        val visible = (0..29).map(::candle)
        val settings = IndicatorSettings(isSmaEnabled = true, isEmaEnabled = true,
            isVwapEnabled = true, isRsiEnabled = true)
        val result = ReplayIndicatorSnapshot.calculate(visible, settings)
        assertEquals(visible.size, result.sma.size)
        assertEquals(visible.size, result.ema.size)
        assertEquals(visible.size, result.vwap.size)
        assertEquals(visible.size, result.rsi.size)
        assertTrue(result.macd.isEmpty())
    }
}
