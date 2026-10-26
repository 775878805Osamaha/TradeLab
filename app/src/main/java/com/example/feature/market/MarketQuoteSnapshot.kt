package com.example.feature.market

import com.example.core.market.VerifiedMarketQuote
import com.example.core.model.Candle
import com.example.core.model.SymbolInfo
import com.example.core.model.Tick

/** Display-only market snapshot. Missing values never become executable zero quotes. */
data class MarketQuoteSnapshot(
    val symbol: SymbolInfo,
    val bid: Double?,
    val ask: Double?,
    val last: Double?,
    val provider: String,
    val providerTimestamp: Long?,
    val freshness: Freshness,
    val comparisonPrice: Double?,
    val change: Double?,
    val changePercent: Double?,
    val history: List<Candle>
) {
    enum class Freshness { LIVE, STALE, UNAVAILABLE }
    val spread: Double? get() = if (freshness == Freshness.LIVE && bid != null && ask != null) ask - bid else null

    companion object {
        fun from(symbol: SymbolInfo, tick: Tick?, candles: List<Candle>, now: Long): MarketQuoteSnapshot {
            val valid = tick?.takeIf {
                it.symbol == symbol.symbol && it.bid.isFinite() && it.ask.isFinite() &&
                    it.bid > 0 && it.ask >= it.bid && it.timestamp <= now &&
                    ((symbol.category == "Crypto" && it.source in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL")) ||
                        (symbol.symbol in VerifiedMarketQuote.forexSymbols && it.source == "BIQUOTE_REST"))
            }
            val fresh = VerifiedMarketQuote.isVerified(valid, symbol.symbol, now)
            val history = candles.filter { it.symbol == symbol.symbol && it.closeTime <= now &&
                it.openTime >= now - 86_400_000L && it.close.isFinite() && it.close > 0 }
                .distinctBy { it.openTime }.sortedBy { it.openTime }
            // Only a complete 24-hour comparison window can be labelled as a 24h change.
            val reference = history.firstOrNull()?.takeIf { now - it.openTime >= 85_500_000L }?.open
                ?.takeIf { it.isFinite() && it > 0 }
            val last = valid?.let { (it.bid / 2) + (it.ask / 2) }
            val change = if (fresh && last != null && reference != null) last - reference else null
            return MarketQuoteSnapshot(symbol, valid?.bid, valid?.ask, last,
                if (symbol.symbol in VerifiedMarketQuote.forexSymbols) "Biquote MT5" else if (symbol.category == "Crypto") "Binance Spot" else "غير مدعوم",
                valid?.timestamp, if (fresh) Freshness.LIVE else if(valid != null) Freshness.STALE else Freshness.UNAVAILABLE,
                reference, change, change?.let { it / reference!! * 100 }?.takeIf { it.isFinite() }, history)
        }
    }
}
