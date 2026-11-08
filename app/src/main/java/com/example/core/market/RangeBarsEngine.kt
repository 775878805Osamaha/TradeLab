package com.example.core.market

import com.example.core.model.Candle

/** A single actual cTrader historical BID quote (not synthetic OHLC). */
data class RangePriceTick(val timestamp: Long, val price: Double)

/** The broker returned too many genuine ticks for a safe in-memory window. */
class RangeTickHistoryTooDenseException(message: String) : IllegalStateException(message)

/** Factual counters from the exact BID quote sequence used to build the chart.
 * They distinguish real quote jumps from rendering artifacts, but never
 * assume that a large jump proves the broker missed data. */
data class RangeTickDiagnostics(
    val quoteCount: Int = 0,
    val sameMillisecondQuotes: Int = 0,
    val jumpsOverOneRange: Int = 0,
    val largestQuoteJumpTicks: Long = 0L,
    val longestQuotePauseMillis: Long = 0L,
    val oversizedCandles: Int = 0
)

data class VerifiedRangeBars(
    val candles: List<Candle>,
    val diagnostics: RangeTickDiagnostics,
    /** The final observed bar has not yet covered the configured price range. */
    val hasIncompleteLastBar: Boolean = false
)

/**
 * Fixed price-range bars built from genuine, ordered cTrader BID quotes.
 * The range is multiples of the instrument's verified minimum price step,
 * not quote count or ATR. Missing intermediate prices are NEVER fabricated.
 *
 * The same verified accumulator also supports append-only updates when the
 * historical quote prefix is proven identical, without changing the rules
 * for closing bars, quote gaps, Replay or the forming last bar.
 */
object RangeBarsEngine {
    fun build(
        symbol: String,
        ticks: List<RangePriceTick>,
        tickSize: Double,
        sizeInPriceTicks: Int,
        source: String,
        includeIncomplete: Boolean = false,
        cancellationCheckpoint: () -> Unit = {}
    ): List<Candle> = buildVerified(symbol, ticks, tickSize, sizeInPriceTicks,
        source, includeIncomplete, cancellationCheckpoint).candles

    fun buildVerified(
        symbol: String,
        ticks: List<RangePriceTick>,
        tickSize: Double,
        sizeInPriceTicks: Int,
        source: String,
        includeIncomplete: Boolean = false,
        cancellationCheckpoint: () -> Unit = {}
    ): VerifiedRangeBars = VerifiedRangeAccumulator(symbol, tickSize, sizeInPriceTicks, source)
        .apply { append(ticks, cancellationCheckpoint) }
        .snapshot(includeIncomplete)
}
