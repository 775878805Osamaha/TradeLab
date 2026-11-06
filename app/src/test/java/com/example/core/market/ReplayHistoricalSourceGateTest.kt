package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class ReplayHistoricalSourceGateTest {
    private fun candle(symbol: String, source: String, time: Long = 0L) = Candle(
        symbol, Timeframe.M1, time, time + 60_000L,
        100.0, 102.0, 99.0, 101.0, 10.0, source
    )

    @Test fun rejectsLegacyForexReplayEvenWhenItWasSavedLocally() {
        val saved = listOf(candle("XAUUSD", "BIQUOTE_HISTORICAL"))
        assertFalse(ReplayHistoricalSourceGate.isTrusted(
            "XAUUSD", Timeframe.M1, saved, "ctrader:demo:123:42"))
        assertFalse(ReplayHistoricalSourceGate.isCurrent("XAUUSD", "BIQUOTE_HISTORICAL", "ctrader:demo:123:42"))
    }

    @Test fun rejectsForexHistoryFromAnotherAccountOrBrokerSymbol() {
        val saved = listOf(candle("XAUUSD", "ctrader:demo:123:42"))
        assertTrue(ReplayHistoricalSourceGate.isTrusted(
            "XAUUSD", Timeframe.M1, saved, "ctrader:demo:123:42"))
        assertFalse(ReplayHistoricalSourceGate.isTrusted(
            "XAUUSD", Timeframe.M1, saved, "ctrader:live:123:42"))
        assertFalse(ReplayHistoricalSourceGate.isTrusted(
            "XAUUSD", Timeframe.M1, saved, "ctrader:demo:456:42"))
        assertFalse(ReplayHistoricalSourceGate.isTrusted(
            "XAUUSD", Timeframe.M1, saved, null))
    }

    @Test fun rejectsMixedOrWrongSymbolCheckpoints() {
        val selected = "ctrader:demo:123:42"
        assertFalse(ReplayHistoricalSourceGate.isTrusted("XAUUSD", Timeframe.M1,
            listOf(candle("XAUUSD", selected), candle("XAUUSD", "ctrader:demo:789:42", 60_000L)), selected))
        assertFalse(ReplayHistoricalSourceGate.isTrusted("XAUUSD", Timeframe.M1,
            listOf(candle("EURUSD", selected)), selected))
        assertFalse(ReplayHistoricalSourceGate.isTrusted("XAUUSD", Timeframe.M1,
            listOf(candle("XAUUSD", selected).copy(timeframe = Timeframe.M5)), selected))
        assertFalse(ReplayHistoricalSourceGate.isTrusted("XAUUSD", Timeframe.M1,
            emptyList(), selected))
    }

    @Test fun cryptoReplayAcceptsOnlyBinanceHistoricalSources() {
        val real = listOf(candle("BTCUSDT", "BINANCE_HISTORICAL"),
            candle("BTCUSDT", "BINANCE_HISTORICAL_CACHED", 60_000L))
        assertTrue(ReplayHistoricalSourceGate.isTrusted("BTCUSDT", Timeframe.M1, real, null))
        assertFalse(ReplayHistoricalSourceGate.isTrusted("BTCUSDT", Timeframe.M1,
            listOf(candle("BTCUSDT", "ctrader:demo:123:42")), null))
        assertFalse(ReplayHistoricalSourceGate.isTrusted("BTCUSDT", Timeframe.M1,
            listOf(candle("BTCUSDT", "FAKE")), null))
    }

    @Test fun explicitlyImportedTrainingRetainsItsSeparateAttribution() {
        val imported = listOf(candle("XAUUSD", "USER_IMPORTED:broker-export"))
        assertTrue(ReplayHistoricalSourceGate.isTrusted("XAUUSD", Timeframe.M1, imported, null))
        assertTrue(ReplayHistoricalSourceGate.isCurrent("XAUUSD", imported.first().source, null))
        assertFalse(ReplayHistoricalSourceGate.isTrusted("XAUUSD", Timeframe.M1,
            listOf(candle("XAUUSD", "USER_IMPORTED:")), null))
    }
}
