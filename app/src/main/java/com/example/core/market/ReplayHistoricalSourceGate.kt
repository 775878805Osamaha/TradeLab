package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe

/**
 * A saved replay is not proof of market provenance. In particular, checkpoints
 * written before the cTrader migration must not resurrect obsolete FX prices.
 * Explicitly imported CSV is a separate, visibly attributed training mode.
 */
object ReplayHistoricalSourceGate {
    private val binanceSources = setOf("BINANCE_HISTORICAL", "BINANCE_HISTORICAL_CACHED")

    fun isTrusted(
        symbol: String,
        timeframe: Timeframe,
        candles: List<Candle>,
        selectedCTraderSource: String?
    ): Boolean {
        if (candles.isEmpty() || candles.any { it.symbol != symbol || it.timeframe != timeframe }) return false
        val sources = candles.mapTo(HashSet()) { it.source }
        if (sources.size == 1 && sources.first().startsWith("USER_IMPORTED:") &&
            sources.first().length > "USER_IMPORTED:".length) return true
        return when {
            symbol in VerifiedMarketQuote.forexSymbols ->
                selectedCTraderSource?.startsWith("ctrader:") == true && sources == setOf(selectedCTraderSource)
            symbol == "BTCUSDT" || symbol == "ETHUSDT" -> sources.all { it in binanceSources }
            else -> false
        }
    }

    fun isCurrent(symbol: String, source: String?, selectedCTraderSource: String?): Boolean {
        if (source.isNullOrBlank()) return false
        if (source.startsWith("USER_IMPORTED:") && source.length > "USER_IMPORTED:".length) return true
        return when {
            symbol in VerifiedMarketQuote.forexSymbols ->
                selectedCTraderSource?.startsWith("ctrader:") == true && source == selectedCTraderSource
            symbol == "BTCUSDT" || symbol == "ETHUSDT" -> source in binanceSources
            else -> false
        }
    }
}
