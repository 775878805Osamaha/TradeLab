package com.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.core.market.HistoricalCandleBoundary
import com.example.core.model.Timeframe
import com.example.feature.ctrader.CTraderAuthorization
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test
import org.junit.runner.RunWith

/** Replay must use the exact same provider contract as the chart. */
@RunWith(AndroidJUnit4::class)
class ReplayYearHistoryProviderTest {
    @Test fun historicalForexReplayCannotImportOldBiquoteOrTwelveDataBars() = runBlocking {
        val app=InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as TradeLabApplication
        assumeFalse(CTraderAuthorization.isLinked(app))
        val interval=Timeframe.H1.minutes*60_000L
        val end=HistoricalCandleBoundary.currentOpen(System.currentTimeMillis(),interval)-interval
        val data=runCatching {
            app.marketDataRepository.getOlderChartCandles("EURUSD",Timeframe.H1,end-24*interval,end)
        }
        assertTrue(data.isFailure)
        assertTrue(data.exceptionOrNull()?.message.orEmpty().contains("cTrader"))
    }
}
