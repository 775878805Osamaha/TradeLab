package com.example.core.market

import com.example.core.model.Tick
import org.junit.Assert.*
import org.junit.Test

/** Regression: no old forex provider may unlock live pricing or paper orders. */
class CTraderOnlySourceGateTest {
    private val now = 1_800_000_000_000L

    @Test fun forexAndGoldAcceptOnlyFreshCTraderQuotes() {
        for (symbol in listOf("XAUUSD", "EURUSD", "GBPUSD", "USDJPY")) {
            val tick = Tick(symbol, 100.0, 100.2, timestamp = now, source = "CTRADER_GATEWAY")
            assertTrue(VerifiedMarketQuote.isVerified(tick, symbol, now))
            for (old in listOf("BIQUOTE_REST", "TWELVE_DATA", "DUKASCOPY", "HISTDATA", "BINANCE_WEBSOCKET")) {
                assertFalse("An old provider was accepted for $symbol", VerifiedMarketQuote.isVerified(
                    tick.copy(source = old), symbol, now))
            }
            assertFalse(VerifiedMarketQuote.isVerified(tick, symbol, now + 15_001L))
            assertFalse(VerifiedMarketQuote.isVerified(tick.copy(ask = 99.0), symbol, now))
        }
    }

    @Test fun cryptoRejectsCTraderAndStillAcceptsOfficialBinance() {
        for (symbol in listOf("BTCUSDT", "ETHUSDT")) {
            val tick = Tick(symbol, 60_000.0, 60_002.0, timestamp = now, source = "CTRADER_GATEWAY")
            assertFalse(VerifiedMarketQuote.isVerified(tick, symbol, now))
            assertTrue(VerifiedMarketQuote.isVerified(tick.copy(source = "BINANCE_WEBSOCKET"), symbol, now))
            assertTrue(VerifiedMarketQuote.isVerified(tick.copy(source = "BINANCE_REST_POLL"), symbol, now))
        }
    }
}
