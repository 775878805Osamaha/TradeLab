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
    @Test fun yearOldMinuteGoldLoadsFromOfficialArchiveWithoutAKey() = runBlocking {
        val source = com.example.core.market.DukascopyChartHistoryProvider()
        val from = java.time.Instant.parse("2025-04-30T10:00:00Z").toEpochMilli()
        val candles = source.fetch("XAUUSD", Timeframe.M1, from, from + 299 * 60_000L)
        assertEquals(300, candles.size)
        assertTrue(candles.all { it.source == com.example.core.market.DukascopyChartHistoryProvider.SOURCE })
        assertTrue(candles.all { it.open in 1000.0..10000.0 })
        android.util.Log.i("TradeLabArchive", "year-old gold M1 count=${candles.size} first=${candles.first().openTime} open=${candles.first().open}")
        Unit
    }

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
                app.marketDataRepository.getOlderChartCandles("XAUUSD", tf, from, to)
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
