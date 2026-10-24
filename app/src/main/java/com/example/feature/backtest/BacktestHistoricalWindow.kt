package com.example.feature.backtest

import com.example.core.market.HistoricalCandleBoundary

/** A bounded request for real, completed historical bars, not the live candle. */
internal data class BacktestHistoricalWindow(val first: Long, val last: Long) {
    companion object {
        fun lastClosed(now: Long, interval: Long, bars: Int): BacktestHistoricalWindow {
            require(now >= 0L && interval > 0L) { "Invalid historical clock or timeframe" }
            require(bars in 16..20_000) { "Invalid backtest history length" }
            val currentOpen = HistoricalCandleBoundary.currentOpen(now, interval)
            require(currentOpen >= interval) { "Not enough elapsed time for a closed candle" }
            val last = currentOpen - interval
            val historySpan = Math.multiplyExact((bars - 1).toLong(), interval)
            require(last >= historySpan) { "Insufficient historical timestamp range" }
            return BacktestHistoricalWindow(last - historySpan, last)
        }
    }
}
