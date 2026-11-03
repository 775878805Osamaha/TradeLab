package com.example.feature.ctrader

import com.example.core.model.Timeframe

/**
 * Bounded Open API request windows. Timestamp spans are conservative: smaller
 * periods need short windows, while daily/weekly bars can query longer ranges.
 * There is no fixed total historical depth: callers page by older timestamps.
 */
object CTraderHistoryPaging {
    private const val DAY_MS = 86_400_000L

    fun windowSpan(timeframe: Timeframe):Long = when(timeframe) {
        Timeframe.M1, Timeframe.M3, Timeframe.M5 -> 6L*DAY_MS
        Timeframe.M15 -> 7L*DAY_MS
        Timeframe.M30 -> 15L*DAY_MS
        Timeframe.H1, Timeframe.H2 -> 30L*DAY_MS
        Timeframe.H4 -> 60L*DAY_MS
        Timeframe.D1, Timeframe.W1 -> 89L*DAY_MS
    }
}
