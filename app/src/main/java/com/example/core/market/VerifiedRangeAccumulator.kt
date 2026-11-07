package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Stateful implementation of the exact same genuine BID tick Range rules.
 * When a request appends quotes to an unchanged verified prefix, only the
 * suffix needs price conversion and range-threshold evaluation. A fork is
 * used before updates so cancellation never corrupts a published checkpoint.
 */
class VerifiedRangeAccumulator(
    private val symbol: String,
    private val tickSize: Double,
    private val sizeInPriceTicks: Int,
    private val source: String
) {
    init {
        require(sizeInPriceTicks in 1..100_000) { "Invalid fixed range size" }
        require(tickSize.isFinite() && tickSize > 0.0) { "Invalid symbol tick size" }
        require(source.startsWith("ctrader:")) { "Range history must come from cTrader" }
        require(symbol.isNotBlank()) { "Symbol required" }
    }

    private val closed = ArrayList<Candle>()
    private var openedAt = 0L
    private var open = 0.0
    private var high = 0.0
    private var low = 0.0
    private var close = 0.0
    private var highestTick = 0L
    private var lowestTick = 0L
    private var active = false
    private var closedOnLastQuote = false
    private var lastTimestamp = -1L
    private var lastPriceTick = -1L
    private var processedTicks = 0
    private var sameMillisecondQuotes = 0
    private var jumpsOverOneRange = 0
    private var largestQuoteJumpTicks = 0L
    private var longestQuotePauseMillis = 0L
    private var oversizedCandles = 0

    /** Fork before appending: a cancelled historical request cannot change
     * the previous complete chart or its reusable scan checkpoint. */
    fun fork(): VerifiedRangeAccumulator =
        VerifiedRangeAccumulator(symbol, tickSize, sizeInPriceTicks, source).also { clone ->
            clone.closed.addAll(closed)
            clone.openedAt = openedAt
            clone.open = open; clone.high = high; clone.low = low; clone.close = close
            clone.highestTick = highestTick; clone.lowestTick = lowestTick
            clone.active = active; clone.closedOnLastQuote = closedOnLastQuote
            clone.lastTimestamp = lastTimestamp; clone.lastPriceTick = lastPriceTick
            clone.processedTicks = processedTicks
            clone.sameMillisecondQuotes = sameMillisecondQuotes
            clone.jumpsOverOneRange = jumpsOverOneRange
            clone.largestQuoteJumpTicks = largestQuoteJumpTicks
            clone.longestQuotePauseMillis = longestQuotePauseMillis
            clone.oversizedCandles = oversizedCandles
        }

    private fun candle(endedAt: Long): Candle = Candle(
        symbol = symbol, timeframe = Timeframe.M1,
        openTime = openedAt,
        // Consecutive broker quotes can share a millisecond.
        closeTime = maxOf(openedAt + 1L, endedAt + 1L),
        open = open, high = high, low = low, close = close,
        // Bid quote count is NOT traded volume.
        volume = 0.0, source = source
    )

    private fun isOversized(): Boolean =
        high - low > sizeInPriceTicks.toDouble() * tickSize * 1.5

    fun append(quotes: List<RangePriceTick>, cancellationCheckpoint: () -> Unit = {}) {
        for (tick in quotes) {
            if ((processedTicks and 8191) == 0) cancellationCheckpoint()
            processedTicks++
            closedOnLastQuote = false
            require(tick.timestamp > 0 && tick.timestamp >= lastTimestamp) {
                "Out-of-order range ticks"
            }
            require(tick.price.isFinite() && tick.price > 0.0) { "Invalid range tick price" }
            val exactTicks = tick.price / tickSize
            require(exactTicks.isFinite() && exactTicks in 1.0..Long.MAX_VALUE.toDouble()) {
                "دقة سعر cTrader لا تسمح بحساب حجم المدى المحدد"
            }
            val priceTicks = exactTicks.roundToLong()
            require(abs(exactTicks - priceTicks.toDouble()) <= 0.000001) {
                "أسعار Bid من cTrader لا تتوافق مع Tick Size الحالي ($tickSize)؛ يلزم تصحيح دقة الرمز من الوسيط"
            }
            require(priceTicks > 0L) { "Invalid price precision" }
            if (lastPriceTick > 0L) {
                if (tick.timestamp == lastTimestamp) sameMillisecondQuotes++
                longestQuotePauseMillis = maxOf(longestQuotePauseMillis,
                    tick.timestamp - lastTimestamp)
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
                if (isOversized()) oversizedCandles++
                closed.add(candle(tick.timestamp))
                closedOnLastQuote = true
                // The real closing BID quote starts the next bar. Do not
                // interpolate prices across a broker quote jump.
                openedAt = tick.timestamp
                open = tick.price; high = tick.price; low = tick.price; close = tick.price
                highestTick = priceTicks; lowestTick = priceTicks
            }
        }
    }

    fun snapshot(includeIncomplete: Boolean): VerifiedRangeBars {
        val forming = active && includeIncomplete && !closedOnLastQuote
        val result = ArrayList<Candle>(closed.size + if (forming) 1 else 0)
        result.addAll(closed)
        if (forming) result.add(candle(lastTimestamp))
        return VerifiedRangeBars(result, RangeTickDiagnostics(
            quoteCount = processedTicks,
            sameMillisecondQuotes = sameMillisecondQuotes,
            jumpsOverOneRange = jumpsOverOneRange,
            largestQuoteJumpTicks = largestQuoteJumpTicks,
            longestQuotePauseMillis = longestQuotePauseMillis,
            oversizedCandles = oversizedCandles + if (forming && isOversized()) 1 else 0
        ), hasIncompleteLastBar = forming)
    }
}
