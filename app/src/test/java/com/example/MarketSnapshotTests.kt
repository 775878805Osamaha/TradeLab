package com.example
import com.example.core.market.DefaultSymbols
import com.example.core.model.Tick
import com.example.feature.market.MarketQuoteSnapshot
import org.junit.Assert.*
import org.junit.Test
class MarketSnapshotTests {
    private val gold=DefaultSymbols.getSymbol("XAUUSD")
    @Test fun sourceBindingAndMissingData() {
        val now=100000L
        val forged=Tick("XAUUSD",2000.0,2001.0,timestamp=now,source="BINANCE_WEBSOCKET")
        assertNull(MarketQuoteSnapshot.from(gold,forged,emptyList(),now).last)
        assertNull(MarketQuoteSnapshot.from(gold,null,emptyList(),now).spread)
    }
    @Test fun expiredQuoteNeverHasLiveSpreadOrChange() {
        val tick=Tick("XAUUSD",2000.0,2001.0,timestamp=100000,source="BIQUOTE_REST")
        val stale=MarketQuoteSnapshot.from(gold,tick,emptyList(),120000)
        assertEquals(MarketQuoteSnapshot.Freshness.STALE,stale.freshness)
        assertNull(stale.spread);assertNull(stale.changePercent)
        assertEquals(1.0,MarketQuoteSnapshot.from(gold,tick,emptyList(),100001).spread!!,0.0)
    }
}
