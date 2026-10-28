package com.example

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.referentialEqualityPolicy
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.ui.components.CandlestickChart
import com.example.ui.components.ChartFirstVisibleIndex
import com.example.ui.components.ChartLoadedCandleCount
import com.example.ui.components.ChartPriceIndexReady
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Synthetic rendering scale test, separate from the actual free-source download proof. */
class LargeChartInteractionTest {
    @get:Rule val compose = createComposeRule()

    private fun candle(index: Int): Candle {
        val open = 2_000.0 + index % 100 * 0.1
        val time = 1_700_000_040_000L + index * 60_000L
        return Candle("XAUUSD", Timeframe.M1, time, open=open, high=open+2,
            low=open-2, close=open+0.5, volume=(index % 100).toDouble(),
            closeTime=time+60_000L, source="TEST_FIXTURE")
    }

    @Test fun hundredThousandCandlesRemainPannableAndBackfillKeepsTheVisibleTimeAnchored() {
        val original = List(100_001, ::candle)
        val series = mutableStateOf<List<Candle>>(original, referentialEqualityPolicy())
        compose.setContent {
            MaterialTheme { CandlestickChart(series.value, modifier=Modifier.fillMaxSize()) }
        }
        fun node() = compose.onNodeWithTag("candlestick_canvas").fetchSemanticsNode()
        compose.waitUntil(15_000) { node().config[ChartPriceIndexReady] }
        assertEquals(100_001, node().config[ChartLoadedCandleCount])
        val initial = node().config[ChartFirstVisibleIndex]
        compose.onNodeWithTag("candlestick_canvas").performTouchInput { swipeRight(durationMillis=600) }
        compose.waitForIdle()
        val panned = node().config[ChartFirstVisibleIndex]
        assertTrue("A right drag must expose older candles", panned < initial)
        val visibleTime = original[panned].openTime

        val older = List(500) { candle(it-500) }
        compose.runOnIdle { series.value = older + original }
        compose.waitUntil(15_000) {
            node().config[ChartLoadedCandleCount] == 100_501 && node().config[ChartPriceIndexReady]
        }
        val afterBackfill = node().config[ChartFirstVisibleIndex]
        assertEquals(visibleTime, series.value[afterBackfill].openTime)

        // Updating a live candle with the same list size must produce a fresh index.
        compose.runOnIdle {
            series.value = series.value.toMutableList().apply {
                this[lastIndex] = last().copy(high=2_100.0)
            }
        }
        compose.waitForIdle()
        compose.waitUntil(15_000) { node().config[ChartPriceIndexReady] }
        assertEquals(100_501, node().config[ChartLoadedCandleCount])
        assertEquals(visibleTime, series.value[node().config[ChartFirstVisibleIndex]].openTime)
    }
}
