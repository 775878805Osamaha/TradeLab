package com.example.feature.chart.history

import com.example.core.market.NoHistoricalCandlesException

/**
 * Only an authoritative empty broker page justifies searching older closed
 * sessions. Authentication failures, outages and malformed OHLC must stop
 * immediately; retrying hundreds of date windows only hides the actual error.
 */
internal object ChartHistoryRetryPolicy {
    fun shouldSearchOlderSession(error: Throwable): Boolean = error is NoHistoricalCandlesException
}
