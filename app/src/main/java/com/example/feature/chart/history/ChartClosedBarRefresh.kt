package com.example.feature.chart.history

import com.example.core.market.HistoricalCandleBoundary
import com.example.core.model.Timeframe

/**
 * Closed-bar polling boundaries. Binance bars open on their exchange's UTC
 * grid; cTrader bars use the broker's first opening tick minute instead.
 * Query a small real-history window for cTrader, never a fabricated exact
 * UTC candle opening time, and throttle repeated requests per timeframe.
 */
internal object ChartClosedBarRefresh {
    data class Window(val from: Long, val to: Long, val attemptKey: Long)

    fun window(now: Long, timeframe: Timeframe, brokerTimed: Boolean): Window {
        val interval = timeframe.minutes.toLong() * 60_000L
        val closedTo = HistoricalCandleBoundary.latestClosedRequestTo(now, interval, brokerTimed)
        if (!brokerTimed) return Window(closedTo, closedTo, closedTo)

        // Two nominal intervals cover legitimate broker-open shifts and the
        // previously closed bar, without requesting 250 bars on every poll.
        val from = (closedTo - 2L * interval).coerceAtLeast(0L)
        val cadence = when {
            interval >= 7L * 86_400_000L -> 4L * 3_600_000L
            interval >= 86_400_000L -> 3_600_000L
            interval >= 4L * 3_600_000L -> 15L * 60_000L
            else -> (interval / 4L).coerceIn(60_000L, 15L * 60_000L)
        }
        return Window(from, closedTo, Math.floorDiv(now, cadence))
    }
}
