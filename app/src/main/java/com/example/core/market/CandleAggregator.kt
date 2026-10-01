package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Tick
import com.example.core.model.Timeframe
import kotlin.math.max
import kotlin.math.min

object CandleAggregator {

    /**
     * Aggregates a list of source candles into a higher target timeframe.
     * Strict rules:
     * - Never looks ahead to future candles.
     * - Closes aggregated candle based on interval boundary or last available source candle.
     * - Preserves volume summation and OHLC integrity.
     */
    fun aggregate(sourceCandles: List<Candle>, targetTimeframe: Timeframe): List<Candle> {
        if (sourceCandles.isEmpty()) return emptyList()

        val symbol = sourceCandles.first().symbol
        val intervalMillis = targetTimeframe.minutes * 60_000L
        if (intervalMillis <= 0L) return sourceCandles

        val result = mutableListOf<Candle>()
        var currentBucketStart = -1L
        var open = 0.0
        var high = Double.MIN_VALUE
        var low = Double.MAX_VALUE
        var close = 0.0
        var volume = 0.0
        var lastCloseTime = 0L

        for (c in sourceCandles) {
            val bucketStart = (c.openTime / intervalMillis) * intervalMillis

            if (currentBucketStart != bucketStart) {
                // Finalize previous bucket if exists
                if (currentBucketStart != -1L) {
                    result.add(
                        Candle(
                            symbol = symbol,
                            timeframe = targetTimeframe,
                            openTime = currentBucketStart,
                            open = open,
                            high = high,
                            low = low,
                            close = close,
                            volume = volume,
                            closeTime = min(currentBucketStart + intervalMillis, lastCloseTime)
                        )
                    )
                }

                // Start new bucket
                currentBucketStart = bucketStart
                open = c.open
                high = c.high
                low = c.low
                close = c.close
                volume = c.volume
                lastCloseTime = c.closeTime
            } else {
                // Accumulate within current bucket
                high = max(high, c.high)
                low = min(low, c.low)
                close = c.close
                volume += c.volume
                lastCloseTime = max(lastCloseTime, c.closeTime)
            }
        }

        // Add the active / latest bucket
        if (currentBucketStart != -1L) {
            result.add(
                Candle(
                    symbol = symbol,
                    timeframe = targetTimeframe,
                    openTime = currentBucketStart,
                    open = open,
                    high = high,
                    low = low,
                    close = close,
                    volume = volume,
                    closeTime = min(currentBucketStart + intervalMillis, lastCloseTime)
                )
            )
        }

        return result
    }

    /**
     * Incrementally updates the latest active candle with an incoming live tick.
     * If the tick crosses into a new timeframe interval, a new candle is appended.
     */
    fun updateWithTick(
        candles: List<Candle>,
        tick: Tick,
        timeframe: Timeframe
    ): List<Candle> {
        val intervalMillis = timeframe.minutes * 60_000L
        val tickBucketStart = (tick.timestamp / intervalMillis) * intervalMillis
        val price = tick.last

        if (candles.isEmpty()) {
            return listOf(
                Candle(
                    symbol = tick.symbol,
                    timeframe = timeframe,
                    openTime = tickBucketStart,
                    open = price,
                    high = price,
                    low = price,
                    close = price,
                    volume = if (tick.volume > 0) tick.volume else 1.0,
                    closeTime = tick.timestamp
                )
            )
        }

        val lastCandle = candles.last()
        val mutableList = candles.toMutableList()

        if (lastCandle.openTime == tickBucketStart) {
            // Update current active candle
            val updated = lastCandle.copy(
                high = max(lastCandle.high, price),
                low = min(lastCandle.low, price),
                close = price,
                volume = lastCandle.volume + if (tick.volume > 0) tick.volume else 1.0,
                closeTime = tick.timestamp
            )
            mutableList[mutableList.size - 1] = updated
        } else if (tickBucketStart > lastCandle.openTime) {
            // Start new candle
            val newCandle = Candle(
                symbol = tick.symbol,
                timeframe = timeframe,
                openTime = tickBucketStart,
                open = price,
                high = price,
                low = price,
                close = price,
                volume = if (tick.volume > 0) tick.volume else 1.0,
                closeTime = tick.timestamp
            )
            mutableList.add(newCandle)
        }

        return mutableList
    }
}
