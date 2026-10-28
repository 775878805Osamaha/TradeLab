package com.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.core.market.HistoricalCandleBoundary
import com.example.core.model.Timeframe
import com.example.feature.chart.history.ChartHistoryPaging
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real source coverage, separate from the 100k+ synthetic arithmetic regression. */
@RunWith(AndroidJUnit4::class)
class ChartHistoryProviderPagingTest {
    @Test fun verifiedGoldHistoryPagesBackwardsAcrossEverySupportedTimeframe() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as TradeLabApplication
        for (tf in Timeframe.entries) {
            val interval = tf.minutes * 60_000L
            val end = HistoricalCandleBoundary.currentOpen(System.currentTimeMillis(), interval) - interval
            val recent = app.marketDataRepository.getCandles("XAUUSD", tf, end - 39 * interval, end)
            assertTrue("Recent source coverage unavailable for ${tf.code}", recent.isNotEmpty())
            var requests = 0
            val older = ChartHistoryPaging.before("XAUUSD", tf, recent.first().openTime) { from, to ->
                requests++
                app.marketDataRepository.getCandles("XAUUSD", tf, from, to)
            }
            assertTrue("Older source coverage unavailable for ${tf.code}", older.isNotEmpty())
            assertTrue(older.all { it.openTime < recent.first().openTime })
            val merged = ChartHistoryPaging.merge(recent, older)
            assertEquals(recent.size + older.size, merged.size)
            assertTrue(merged.zipWithNext().all { (a, b) -> a.openTime < b.openTime })
            android.util.Log.i("TradeLabHistoryPaging", "${tf.code} older=${older.size} recent=${recent.size} requests=$requests earliest=${older.first().openTime}")
        }
    }
}
