package com.example.feature.chart.history

/**
 * Bounded coverage plan for the first real OHLC load. Later scans use wider
 * windows than the initial screen request, so a long FX holiday does not
 * require hundreds of redundant small history calls.
 *
 * Broker candle opens may drift away from an exact UTC grid. Adjacent windows
 * meet at one-minute boundaries instead of leaving an interval-wide hole.
 * This plan never creates candles; the provider is queried for every window.
 */
object ChartInitialHistoryScan {
    const val HISTORY_WINDOW_BARS = 500
    private const val BROKER_LOOKBACK_MILLIS = 14L * 86_400_000L
    private const val MAX_WINDOWS = 60

    data class Window(
        val from: Long,
        val to: Long,
        val bars: Int,
        val isInitial: Boolean
    )

    fun windows(
        lastClosedOpen: Long,
        intervalMillis: Long,
        initialBars: Int,
        brokerTimed: Boolean
    ): List<Window> {
        require(lastClosedOpen >= 0L && intervalMillis >= 60_000L && initialBars > 0)
        val result = ArrayList<Window>()
        var end = lastClosedOpen
        var bars = initialBars
        while (end >= 0L && result.size < MAX_WINDOWS &&
            (result.isEmpty() || (brokerTimed && lastClosedOpen - end <= BROKER_LOOKBACK_MILLIS))) {
            val from = (end - (bars - 1L) * intervalMillis).coerceAtLeast(0L)
            result.add(Window(from = from, to = end, bars = bars, isInitial = result.isEmpty()))
            if (from == 0L) break
            end = from - 60_000L
            bars = HISTORY_WINDOW_BARS
        }
        return result
    }
}
