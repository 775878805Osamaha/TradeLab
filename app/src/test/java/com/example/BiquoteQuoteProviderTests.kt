package com.example

import com.example.core.market.BiquoteQuoteProvider
import com.example.core.market.VerifiedMarketQuote
import com.example.core.model.Tick
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.io.IOException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = android.app.Application::class)
class BiquoteQuoteProviderTests {
    private val now = Instant.parse("2026-01-05T12:00:00Z").toEpochMilli()
    private fun body(symbol: String = "XAUUSD", bid: Double = 4000.0, ask: Double = 4000.2,
        timestamp: String = "2026-01-05T12:00:00Z", stale: Boolean = false, state: String = "open") =
        """{"symbol":"$symbol","bid":$bid,"ask":$ask,"last":0,"timestamp":"$timestamp","stale":$stale,"quoteAgeSeconds":0,"marketState":"$state","source":"MetaTrader 5 (Broker 1)"}"""
    @Test fun realBidAskSuppliesMidWhenFxLastIsZero() {
        val tick = BiquoteQuoteProvider().parse(body(), "XAUUSD", now)
        assertEquals(4000.1, tick.last, .00001)
        assertEquals(4000.0, tick.bid, .00001)
        assertEquals(4000.2, tick.ask, .00001)
        assertEquals("BIQUOTE_REST", tick.source)
        assertTrue(VerifiedMarketQuote.isVerified(tick, "XAUUSD", now))
    }
    @Test fun staleAndClosedQuotesCannotUnlockPaperOrders() {
        for (payload in listOf(body(stale = true), body(state = "closed"),
            body(timestamp = "2026-01-05T11:59:00Z"), body(timestamp = "2026-01-05T12:01:00Z"))) {
            try { BiquoteQuoteProvider().parse(payload, "XAUUSD", now); fail("Expired/closed quote accepted") }
            catch (_: IOException) { }
        }
    }
    @Test fun wrongSymbolAndCrossedBidAskAreRejected() {
        for (payload in listOf(body(symbol = "EURUSD"), body(bid = 4001.0, ask = 4000.0), body(bid = -1.0))) {
            try { BiquoteQuoteProvider().parse(payload, "XAUUSD", now); fail("Invalid quote accepted") }
            catch (_: IOException) { }
        }
    }
    @Test fun aSourceNameAloneIsNotProofForAnotherAssetClass() {
        val fake = Tick("XAUUSD", 4000.0, 4001.0, timestamp = now, source = "BINANCE_REST_POLL")
        assertFalse(VerifiedMarketQuote.isVerified(fake, "XAUUSD", now))
        assertFalse(VerifiedMarketQuote.isVerified(fake.copy(symbol = "BTCUSDT", source = "BIQUOTE_REST"), "BTCUSDT", now))
        assertFalse(VerifiedMarketQuote.isVerified(fake.copy(source = "REPLAY"), "XAUUSD", now))
    }
    @Test fun cryptoSourceAndFreshnessChecksRemainStrict() {
        val tick = Tick("BTCUSDT", 60000.0, 60001.0, timestamp = now, source = "BINANCE_WEBSOCKET")
        assertTrue(VerifiedMarketQuote.isVerified(tick, "BTCUSDT", now))
        assertFalse(VerifiedMarketQuote.isVerified(tick, "BTCUSDT", now + 15001L))
        assertFalse(VerifiedMarketQuote.isVerified(tick, "ETHUSDT", now))
    }
    @Test fun marketSpreadUsesTheRealGoldQuoteAndRejectsAnotherSource() {
        val tick = Tick("XAUUSD", 4000.0, 4000.2, timestamp = System.currentTimeMillis(), source = "BIQUOTE_REST")
        val symbol = com.example.core.market.DefaultSymbols.getSymbol("XAUUSD")
        val row = com.example.feature.market.SymbolMarketRow(symbol, tick)
        assertEquals(20.0, row.spreadPips!!, .00001)
        assertNull(com.example.feature.market.SymbolMarketRow(symbol, tick.copy(source = "BINANCE_REST_POLL")).spreadPips)
    }

}
