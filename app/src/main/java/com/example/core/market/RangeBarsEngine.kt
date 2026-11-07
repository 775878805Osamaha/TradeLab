package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlin.math.abs
import kotlin.math.roundToLong

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
 * Fixed price-range bars. `sizeInPriceTicks` means multiples of the symbol's
 * minimum price movement, NOT a count of quote events and NOT an ATR period.
 * A price gap can make a bar wider than the requested size: no intervening
 * quotes or prices are invented to make its geometry look prettier.
 */
object RangeBarsEngine {
    fun build(
        symbol: String,
        ticks: List<RangePriceTick>,
        tickSize: Double,
        sizeInPriceTicks: Int,
        source: String,
        includeIncomplete: Boolean = false
    ): List<Candle> = buildVerified(symbol, ticks, tickSize, sizeInPriceTicks,
        source, includeIncomplete).candles

    fun buildVerified(
        symbol: String,
        ticks: List<RangePriceTick>,
        tickSize: Double,
        sizeInPriceTicks: Int,
        source: String,
        includeIncomplete: Boolean = false
    ): VerifiedRangeBars {
        require(sizeInPriceTicks in 1..100_000) { "Invalid fixed range size" }
        require(tickSize.isFinite() && tickSize > 0.0) { "Invalid symbol tick size" }
        require(source.startsWith("ctrader:")) { "Range history must come from cTrader" }
        require(symbol.isNotBlank()) { "Symbol required" }
        if (ticks.isEmpty()) return VerifiedRangeBars(emptyList(), RangeTickDiagnostics())

        val result = ArrayList<Candle>()
        var openedAt = 0L
        var open = 0.0
        var high = 0.0
        var low = 0.0
        var close = 0.0
        var highestTick = 0L
        var lowestTick = 0L
        var active = false
        var closedOnLastQuote = false
        var lastTimestamp = -1L
        var lastPriceTick = -1L
        var sameMillisecondQuotes = 0
        var jumpsOverOneRange = 0
        var largestQuoteJumpTicks = 0L
        var longestQuotePauseMillis = 0L
        var oversizedCandles = 0

        fun emit(endedAt: Long) {
            if (high - low > sizeInPriceTicks.toDouble() * tickSize * 1.5)
                oversizedCandles++
            result.add(Candle(
                symbol = symbol, timeframe = Timeframe.M1,
                openTime = openedAt,
                // Consecutive broker quotes can share a millisecond.
                closeTime = maxOf(openedAt + 1L, endedAt + 1L),
                open = open, high = high, low = low, close = close,
                // Bid quote count is NOT traded volume.
                volume = 0.0, source = source
            ))
        }

        for (tick in ticks) {
            closedOnLastQuote = false
            require(tick.timestamp > 0 && tick.timestamp >= lastTimestamp) { "Out-of-order range ticks" }
            require(tick.price.isFinite() && tick.price > 0.0) { "Invalid range tick price" }
            val exactTicks = tick.price / tickSize
            require(exactTicks.isFinite() && exactTicks in 1.0..Long.MAX_VALUE.toDouble()) {
                "دقة سعر cTrader لا تسمح بحساب حجم المدى المحدد"
            }
            val priceTicks = exactTicks.roundToLong()
            // Rounding a broker quote to a hard-coded price step subtly
            // changes the threshold and can generate the misaligned candles
            // reported on XAUUSD. Stop, expose the incompatibility and require
            // genuine broker tick-size verification instead of inventing a price.
            require(abs(exactTicks - priceTicks.toDouble()) <= 0.000001) {
                "أسعار Bid من cTrader لا تتوافق مع Tick Size الحالي ($tickSize)؛ يلزم تصحيح دقة الرمز من الوسيط"
            }
            require(priceTicks > 0L) { "Invalid price precision" }
            if (lastPriceTick > 0L) {
                if (tick.timestamp == lastTimestamp) sameMillisecondQuotes++
                longestQuotePauseMillis = maxOf(longestQuotePauseMillis, tick.timestamp - lastTimestamp)
                val priceJump = abs(priceTicks - lastPriceTick)
                largestQuoteJumpTicks = maxOf(largestQuoteJumpTicks, priceJump)
                if (priceJump >= sizeInPriceTicks) jumpsOverOneRange++
            }
            lastTimestamp = tick.timestamp
            lastPriceTick = priceTicks
            if (!active) {
                openedAt = tick.timestamp
                open = tick.price; high = tick.price; low = tick.price; close = tick.price
                highestTick = priceTicks; lowestTick = priceTicks
                active = true
            } else {
                high = maxOf(high, tick.price)
                low = minOf(low, tick.price)
                close = tick.price
                highestTick = maxOf(highestTick, priceTicks)
                lowestTick = minOf(lowestTick, priceTicks)
            }
            if (highestTick - lowestTick >= sizeInPriceTicks.toLong()) {
                emit(tick.timestamp)
                closedOnLastQuote = true
                // The closing quote is also the first *observed* quote of the
                // next range. Starting on the following tick introduces an
                // artificial gap between consecutive bars, particularly on
                // fast-moving XAUUSD, even though no broker quote was missed.
                // Reuse the real closing price as the next open; do not
                // interpolate any untraded prices across a large quote jump.
                openedAt = tick.timestamp
                open = tick.price
                high = tick.price
                low = tick.price
                close = tick.price
                highestTick = priceTicks
                lowestTick = priceTicks
            }
        }
        // The next bar was anchored at the last close, but no *new* quote has
        // arrived yet. Do not draw a duplicate zero-range projection candle.
        val hasIncompleteLastBar = active && includeIncomplete && !closedOnLastQuote
        if (hasIncompleteLastBar) emit(lastTimestamp)
        return VerifiedRangeBars(result, RangeTickDiagnostics(
            quoteCount = ticks.size,
            sameMillisecondQuotes = sameMillisecondQuotes,
            jumpsOverOneRange = jumpsOverOneRange,
            largestQuoteJumpTicks = largestQuoteJumpTicks,
            longestQuotePauseMillis = longestQuotePauseMillis,
            oversizedCandles = oversizedCandles
        ), hasIncompleteLastBar = hasIncompleteLastBar)
    }
}
