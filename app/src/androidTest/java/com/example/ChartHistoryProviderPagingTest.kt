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
    @Test fun downloadsOver100000ActualGoldMinuteCandles() = runBlocking {
        kotlinx.coroutines.withTimeout(12L*60_000) {
            val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as TradeLabApplication
            val from = java.time.Instant.parse("2025-04-30T10:00:00Z").toEpochMilli()
            val directory=java.io.File(app.cacheDir,"histdata-history-v1")
            // Fetch the actual public free annual ZIP once, then exercise the
            // production repository/pager over its persisted M1 data.
            val source=com.example.core.market.HistDataChartHistoryProvider(directory)
            var candles=source.fetch("XAUUSD",Timeframe.M1,from,from+299*60_000L)
            assertTrue(candles.isNotEmpty())
            var pages=0
            var result: com.example.feature.chart.history.ChartHistoryDownload.Result? = null
            for (attempt in 0..2) {
                try {
                    result = com.example.feature.chart.history.ChartHistoryDownload.run(candles,pauseMillis=250,
                fetchBefore={oldest ->
                    ChartHistoryPaging.before("XAUUSD",Timeframe.M1,oldest) { start,end ->
                        app.marketDataRepository.getOlderChartCandles("XAUUSD",Timeframe.M1,start,end)
                    }
                },append={page ->
                    candles=ChartHistoryPaging.merge(candles,page)
                    if(++pages%10==0) android.util.Log.i("TradeLabDeepHistoryProgress","pages=$pages actualCandles=${candles.size}")
                })
                    break
                } catch (error: com.example.core.market.MarketDataRequestException) {
                    val transient = error.message?.let { it.contains("network failure") } == true
                    if (!transient || attempt==2) throw error
                    // Exercise the same retained-history resume available to the user.
                    android.util.Log.i("TradeLabDeepHistoryProgress","retry=${attempt+1} retainedActualCandles=${candles.size}")
                    kotlinx.coroutines.delay(60_000L)
                }
            }
            assertEquals(com.example.feature.chart.history.ChartHistoryDownload.Result.TARGET_REACHED,result)
            assertTrue(candles.size>100_000)
            val allowed = setOf(com.example.core.market.DukascopyChartHistoryProvider.SOURCE,"BIQUOTE_HISTORICAL",com.example.core.market.HistDataChartHistoryProvider.SOURCE)
            assertTrue(candles.all { it.source in allowed })
            assertTrue(candles.zipWithNext().all { (a,b) -> a.openTime<b.openTime })
            val archived = candles.count { it.source==com.example.core.market.DukascopyChartHistoryProvider.SOURCE }
            val histData=candles.count { it.source==com.example.core.market.HistDataChartHistoryProvider.SOURCE }
            assertTrue("The free source must supply the large download",histData>100_000)
            val offline=okhttp3.OkHttpClient.Builder().addInterceptor { throw java.io.IOException("Offline verification") }.build()
            assertEquals(300,com.example.core.market.HistDataChartHistoryProvider(directory,offline)
                .fetch("XAUUSD",Timeframe.M1,from,from+299*60_000L).size)
            android.util.Log.i("TradeLabDeepHistory", """{"symbol":"XAUUSD","timeframe":"M1","actualCandles":${candles.size},"archiveCandles":$archived,"histDataCandles":$histData,"recentProviderCandles":${candles.size-archived-histData},"pages":$pages,"oldest":${candles.first().openTime},"newest":${candles.last().openTime},"synthetic":false,"offlineCacheVerified":true}""")
        }
        Unit
    }

    @Test fun yearOldMinuteGoldLoadsFromFreeHistoryWithoutAKey() = runBlocking {
        val app=InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as TradeLabApplication
        val from = java.time.Instant.parse("2025-04-30T10:00:00Z").toEpochMilli()
        val candles = app.marketDataRepository.getOlderChartCandles("XAUUSD", Timeframe.M1, from, from + 299 * 60_000L)
        assertEquals(300, candles.size)
        assertTrue(candles.all { it.source in setOf(com.example.core.market.DukascopyChartHistoryProvider.SOURCE,com.example.core.market.HistDataChartHistoryProvider.SOURCE) })
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
