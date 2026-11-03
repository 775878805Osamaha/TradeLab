package com.example

import com.example.core.market.VerifiedMarketQuote
import com.example.core.model.Tick
import org.junit.Assert.*
import org.junit.Test

/** Fixed two-provider product contract: never accept quotes from a retired source. */
class ExclusiveMarketSourcePolicyTest {
    private val now=1_800_000_000_000L

    @Test fun everyForexAndMetalQuoteMustBeFromCTrader() {
        for(symbol in VerifiedMarketQuote.forexSymbols) {
            val quote=Tick(symbol,2500.0,2500.25,timestamp=now,source="CTRADER_REST")
            assertTrue(symbol,VerifiedMarketQuote.isVerified(quote,symbol,now))
            for(retired in listOf("BIQUOTE_REST","TWELVE_DATA_HISTORICAL",
                "DUKASCOPY_BID_HISTORY","HISTDATA_BID_HISTORY","BINANCE_WEBSOCKET")) {
                assertFalse(symbol+" rejects "+retired,
                    VerifiedMarketQuote.isVerified(quote.copy(source=retired),symbol,now))
            }
        }
    }

    @Test fun allCryptoQuotesMustBeFromBinance() {
        for(symbol in listOf("BTCUSDT","ETHUSDT")) {
            val quote=Tick(symbol,300.0,300.25,timestamp=now,source="BINANCE_WEBSOCKET")
            assertTrue(VerifiedMarketQuote.isVerified(quote,symbol,now))
            assertTrue(VerifiedMarketQuote.isVerified(quote.copy(source="BINANCE_REST_POLL"),symbol,now))
            assertFalse(VerifiedMarketQuote.isVerified(quote.copy(source="CTRADER_REST"),symbol,now))
            assertFalse(VerifiedMarketQuote.isVerified(quote.copy(source="BIQUOTE_REST"),symbol,now))
        }
    }

    @Test fun staleOrSwappedQuotesAreNeverAuthorized() {
        val gold=Tick("XAUUSD",2500.0,2500.25,timestamp=now-20_000,source="CTRADER_REST")
        assertFalse(VerifiedMarketQuote.isVerified(gold,"XAUUSD",now))
        assertFalse(VerifiedMarketQuote.isVerified(gold.copy(timestamp=now),"EURUSD",now))
        assertFalse(VerifiedMarketQuote.isVerified(gold.copy(timestamp=now,ask=2499.0),"XAUUSD",now))
    }
}
