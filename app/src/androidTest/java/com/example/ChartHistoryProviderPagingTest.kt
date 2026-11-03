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

/** Exclusive market-source regression. No third-party FX history is permitted. */
@RunWith(AndroidJUnit4::class)
class ChartHistoryProviderPagingTest {
    @Test fun goldCannotFallBackToLegacyHistoryWhileCTraderIsUnlinked() = runBlocking {
        val app=InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as TradeLabApplication
        assumeFalse(CTraderAuthorization.isLinked(app))
        assertTrue(app.marketDataRepository.supportsHistoricalSymbol("XAUUSD"))
        assertTrue(app.cTraderChartSource.isSelectedFor("XAUUSD"))
        val interval=Timeframe.M15.minutes*60_000L
        val to=HistoricalCandleBoundary.currentOpen(System.currentTimeMillis(),interval)-interval
        val result=runCatching {
            app.marketDataRepository.getCandles("XAUUSD",Timeframe.M15,to-interval,to)
        }
        assertTrue("Must fail closed without cTrader account",result.isFailure)
        assertTrue("No Biquote/archive fallback allowed",result.exceptionOrNull()?.message.orEmpty().contains("cTrader"))
    }

    @Test fun cryptoIsNotOwnedByCTrader() {
        val app=InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as TradeLabApplication
        assertFalse(app.cTraderChartSource.isSelectedFor("BTCUSDT"))
        assertFalse(app.cTraderChartSource.isSelectedFor("ETHUSDT"))
        assertTrue(app.marketDataRepository.supportsHistoricalSymbol("BTCUSDT"))
    }
}
