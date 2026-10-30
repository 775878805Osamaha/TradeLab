package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import java.math.BigDecimal
import java.math.RoundingMode

/** Transport-independent Open API decoder. Never supplies credentials or executes orders. */
object CTraderTrendbars {
    data class Bar(
        val utcTimestampInMinutes: Long,
        val low: Long,
        val deltaOpen: Long,
        val deltaHigh: Long,
        val deltaClose: Long,
        val volume: Long
    )

    /** H2 is not an Open API period; callers must aggregate H1 explicitly. */
    fun period(timeframe: Timeframe): Int? = when (timeframe) {
        Timeframe.M1 -> 1
        Timeframe.M3 -> 3
        Timeframe.M5 -> 5
        Timeframe.M15 -> 7
        Timeframe.M30 -> 8
        Timeframe.H1 -> 9
        Timeframe.H2 -> null
        Timeframe.H4 -> 10
        Timeframe.D1 -> 12
        Timeframe.W1 -> 13
    }

    /**
     * Closed bars only, for replay/backtests. Reject corrupt batches atomically; retain
     * real gaps. sourceKey must identify environment/account/symbol, not a display name.
     * Prices use fixed 1e5 scaling regardless of symbol digits; volume is tick count.
     * See https://help.ctrader.com/open-api/symbol-data/ and model-messages/.
     */
    fun decode(
        bars: List<Bar>, symbol: String, timeframe: Timeframe, digits: Int,
        sourceKey: String, from: Long, to: Long, now: Long
    ): List<Candle> {
        require(symbol.isNotBlank() && sourceKey.isNotBlank())
        require(digits in 0..5)
        require(from >= 0 && to > from && now >= 0)
        require(period(timeframe) != null) { "No native cTrader period for $timeframe" }
        val source = "ctrader:$sourceKey"
        val closedUntil = minOf(to, now)
        val candles = bars.map { bar ->
            require(bar.utcTimestampInMinutes in 0..0xffffffffL)
            require(bar.low > 0 && bar.volume >= 0)
            require(bar.deltaOpen >= 0 && bar.deltaClose >= 0 && bar.deltaHigh >= 0)
            require(bar.deltaOpen <= bar.deltaHigh && bar.deltaClose <= bar.deltaHigh)
            fun price(delta: Long): Double = BigDecimal.valueOf(Math.addExact(bar.low, delta), 5)
                .setScale(digits, RoundingMode.HALF_EVEN).toDouble()
            val openTime = Math.multiplyExact(bar.utcTimestampInMinutes, 60_000L)
            Candle(symbol, timeframe, openTime,
                Math.addExact(openTime, timeframe.minutes * 60_000L),
                price(bar.deltaOpen), price(bar.deltaHigh), price(0), price(bar.deltaClose),
                bar.volume.toDouble(), source)
        }
        // Exact boundary filtering is necessary: API responses may include the live bar.
        val closed = candles.filter { it.openTime >= from && it.closeTime <= closedUntil }
        if (closed.isEmpty()) return emptyList()
        return HistoricalCandleIntegrity.validate(closed, from, closedUntil, source, symbol, timeframe)
    }
}
