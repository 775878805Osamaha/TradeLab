package com.example.core.market

/**
 * A bounded, fully verified BID quote window. Keep useful overlapping history
 * on either side of the *visible* request so that short backward/forward pans
 * do not trigger a fresh cTrader download for quotes we already received.
 *
 * Never pass [Window.ticks] directly to Replay: the renderer must select the
 * exact requested interval with [RangeTickWindowReuse.between] first, so a
 * retained future quote can never become visible before the Replay cutoff.
 */
object RangeTickRollingWindow {
    const val MAX_RETAINED_SPAN_MILLIS = 7L * 24L * 3_600_000L

    data class Window(
        val symbol: String,
        val source: String,
        val from: Long,
        val to: Long,
        val ticks: List<RangePriceTick>
    )

    fun extend(
        previous: Window?,
        visible: Window,
        maxTicks: Int = RangeTickBatchLoader.MAX_WINDOW_TICKS,
        maxSpanMillis: Long = MAX_RETAINED_SPAN_MILLIS
    ): Window {
        require(maxTicks > 0 && maxSpanMillis > 0)
        require(visible.from > 0 && visible.to >= visible.from)
        require(visible.ticks.size <= maxTicks)
        val old = previous?.takeIf {
            it.symbol == visible.symbol && it.source == visible.source &&
                visible.from <= it.to && visible.to >= it.from
        } ?: return visible

        // Exactly the same genuine broker interval is already covered.
        if (visible.from >= old.from && visible.to <= old.to) return old

        val older = if (visible.from < old.from)
            RangeTickWindowReuse.between(visible.ticks, visible.from, old.from - 1L)
            else emptyList()
        val newer = if (visible.to > old.to)
            RangeTickWindowReuse.between(visible.ticks, old.to + 1L, visible.to)
            else emptyList()
        val combinedSize = older.size.toLong() + old.ticks.size + newer.size
        val unionFrom = minOf(old.from, visible.from)
        val unionTo = maxOf(old.to, visible.to)

        // The *entire* requested window is always retained. On old/low-memory
        // devices drop spare cache history rather than dropping individual
        // same-millisecond BID quotes or producing a discontinuous coverage.
        if (combinedSize > maxTicks || unionTo - unionFrom > maxSpanMillis) return visible

        return Window(visible.symbol, visible.source, unionFrom, unionTo,
            ArrayList<RangePriceTick>(combinedSize.toInt()).apply {
                addAll(older)
                addAll(old.ticks)
                addAll(newer)
            })
    }

    /** Estimate a safe first broker time slice from verified measured density. */
    fun initialSliceMillis(window: Window?): Long = if (window == null) 3_600_000L
        else RangeTickBatchLoader.nextSliceMillis(window.ticks.size,
            (window.to - window.from + 1L).coerceAtLeast(1L))
}
