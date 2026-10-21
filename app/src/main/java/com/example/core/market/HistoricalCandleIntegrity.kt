package com.example.core.market

import com.example.core.model.Candle

/**
 * Strict gate for historical candles used by replay and backtesting.
 * No synthetic candles, future candles, duplicate timestamps or malformed OHLC.
 * All timestamps are UTC epoch milliseconds.
 */
object HistoricalCandleIntegrity {
    fun validate(
        candles: List<Candle>,
        requestedFrom: Long,
        requestedTo: Long,
        expectedSource: String? = null,
        expectedSymbol: String? = null,
        expectedTimeframe: com.example.core.model.Timeframe? = null
    ): List<Candle> {
        require(requestedFrom >= 0 && requestedTo > requestedFrom) { "Invalid historical range" }
        if (candles.isEmpty()) return emptyList()

        val ordered = candles.sortedBy { it.openTime }
        var previousOpen = Long.MIN_VALUE
        for (candle in ordered) {
            if (expectedSymbol != null) {
                require(candle.symbol.equals(expectedSymbol, ignoreCase = true)) { "Unexpected historical symbol" }
            }
            if (expectedTimeframe != null) {
                require(candle.timeframe == expectedTimeframe) { "Unexpected historical timeframe" }
            }
            require(candle.openTime >= requestedFrom && candle.openTime < requestedTo) {
                "Historical candle outside requested range: ${candle.openTime}"
            }
            require(candle.openTime > previousOpen) {
                "Duplicate historical candle timestamp: ${candle.openTime}"
            }
            require(candle.open.isFinite() && candle.high.isFinite() &&
                candle.low.isFinite() && candle.close.isFinite() && candle.volume.isFinite()) {
                "Non-finite historical candle"
            }
            require(candle.open > 0 && candle.high > 0 && candle.low > 0 && candle.close > 0) {
                "Non-positive historical price"
            }
            require(candle.isValid()) { "Invalid historical OHLC" }
            require(candle.closeTime <= requestedTo) { "Incomplete candle outside requested range" }
            // Binance W1 candles begin Monday 00:00 UTC (four days after Unix epoch).
            // Do not exempt weekly bars from timestamp validation.
            val intervalMillis = candle.timeframe.minutes * 60_000L
            val mondayOffset = 4L * 24 * 60 * 60 * 1000
            val offset = if (candle.timeframe.minutes == 10_080) mondayOffset else 0L
            require(Math.floorMod(candle.openTime - offset, intervalMillis) == 0L) {
                "Misaligned candle timestamp"
            }
            if (expectedSource != null) {
                require(candle.source == expectedSource) { "Unexpected historical data source" }
            }
            previousOpen = candle.openTime
        }
        return ordered
    }
}
