package com.example.core.market

import com.example.core.model.Tick

/** Source AND symbol binding, shared by display, subscriptions and paper-order gates. */
object VerifiedMarketQuote {
    val forexSymbols = setOf("XAUUSD", "XAGUSD", "EURUSD", "GBPUSD", "USDJPY", "USDCHF",
        "AUDUSD", "USDCAD", "NZDUSD", "EURJPY", "GBPJPY", "EURGBP")
    fun supports(symbol: String) = symbol in forexSymbols || symbol in setOf("BTCUSDT", "ETHUSDT")
    fun isVerified(tick: Tick?, symbol: String, now: Long = System.currentTimeMillis()): Boolean {
        if (tick == null || tick.symbol != symbol || !DataIntegrityValidator.validateTick(tick).isValid ||
            now - tick.timestamp !in 0L..15_000L) return false
        return if (symbol in forexSymbols) tick.source == "BIQUOTE_REST"
        else symbol in setOf("BTCUSDT", "ETHUSDT") && tick.source in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL")
    }
}

class MarketDataRequestException(message: String, cause: Throwable? = null) : java.io.IOException(message, cause)
