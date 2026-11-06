package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlin.math.roundToLong

/** A single actual cTrader historical BID quote (not synthetic OHLC). */
data class RangePriceTick(val timestamp: Long, val price: Double)

/** The broker returned too many genuine ticks for a safe in-memory window. */
class RangeTickHistoryTooDenseException(message: String) : IllegalStateException(message)

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
    ): List<Candle> {
        require(sizeInPriceTicks in 1..100_000) { "Invalid fixed range size" }
        require(tickSize.isFinite() && tickSize > 0.0) { "Invalid symbol tick size" }
        require(source.startsWith("ctrader:")) { "Range history must come from cTrader" }
        require(symbol.isNotBlank()) { "Symbol required" }
        if (ticks.isEmpty()) return emptyList()

        val result = ArrayList<Candle>()
        var openedAt = 0L
        var open = 0.0
        var high = 0.0
        var low = 0.0
        var close = 0.0
        var highestTick = 0L
        var lowestTick = 0L
        var active = false
        var lastTimestamp = -1L

        fun emit(endedAt: Long) {
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
            require(tick.timestamp > 0 && tick.timestamp >= lastTimestamp) { "Out-of-order range ticks" }
            require(tick.price.isFinite() && tick.price > 0.0) { "Invalid range tick price" }
            val priceTicks = (tick.price / tickSize).roundToLong()
            require(priceTicks > 0L) { "Invalid price precision" }
            lastTimestamp = tick.timestamp
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
                active = false
            }
        }
        if (active && includeIncomplete) emit(lastTimestamp)
        return result
    }
}
