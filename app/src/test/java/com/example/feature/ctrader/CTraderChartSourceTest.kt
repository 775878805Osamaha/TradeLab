package com.example.feature.ctrader

import com.example.core.market.VerifiedMarketQuote
import com.example.core.model.Tick
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class CTraderChartSourceTest {
    private fun bar(at:Long,open:Double,high:Double,low:Double,close:Double) =
        CTraderReadOnlyMarketApi.BrokerCandle(at,open,high,low,close,10)

    @Test fun twoRealHourBarsCreateOneRealH2Bar() {
        val start=7_200_000L*300000L
        val actual=CTraderBarConversion.aggregateH2("EURUSD",listOf(
            bar(start,1.1,1.2,1.05,1.15),
            bar(start+3_600_000L,1.15,1.25,1.12,1.18)
        ))
        assertEquals(1,actual.size)
        val candle=actual.single()
        assertEquals("EURUSD",candle.symbol)
        assertEquals(Timeframe.H2,candle.timeframe)
        assertEquals("CTRADER_HISTORICAL",candle.source)
        assertEquals(1.1,candle.open,0.000001)
        assertEquals(1.25,candle.high,0.000001)
        assertEquals(1.05,candle.low,0.000001)
        assertEquals(1.18,candle.close,0.000001)
        assertEquals(20.0,candle.volume,0.000001)
    }

    @Test fun neverInventMissingH2CandleAcrossMarketGaps() {
        val start=7_200_000L*300000L
        val result=CTraderBarConversion.aggregateH2("XAUUSD",listOf(
            bar(start,2000.0,2001.0,1999.0,2000.0),
            bar(start+7_200_000L,2000.0,2003.0,2000.0,2001.0)
        ))
        assertTrue(result.isEmpty())
    }

    @Test fun onlyFreshBrokerQuoteCanBeUsedForPaperOrders() {
        val now=System.currentTimeMillis()
        val good=Tick("XAUUSD",2500.0,2500.25,2500.125,now-500L,"CTRADER_REST")
        assertTrue(VerifiedMarketQuote.isVerified(good,"XAUUSD",now))
        assertFalse(VerifiedMarketQuote.isVerified(good.copy(timestamp=now-60_000L),"XAUUSD",now))
        assertFalse(VerifiedMarketQuote.isVerified(good.copy(source="FAKE_BROKER"),"XAUUSD",now))
        assertFalse(VerifiedMarketQuote.isVerified(good.copy(symbol="EURUSD"),"XAUUSD",now))
    }
}
