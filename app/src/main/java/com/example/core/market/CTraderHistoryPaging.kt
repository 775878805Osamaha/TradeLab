package com.example.core.market

/**
 * cTrader returns historical bars newest-first under a count limit. A response
 * may still contain valid bars when hasMore=true; never discard those bars or
 * recursively split the request into one-candle API calls.
 */
internal object CTraderHistoryPaging {
    data class Page<T>(val items: List<T>, val hasMore: Boolean)

    suspend fun <T> load(
        from: Long,
        to: Long,
        interval: Long,
        timeOf: (T) -> Long,
        fetch: suspend (start: Long, end: Long, count: Int) -> Page<T>,
    ): List<T> {
        require(from >= 0L && to >= from && interval > 0L) { "Invalid cTrader history range" }
        // One millisecond is reserved for the broker's exclusive upper bound.
        val slotsPerWindow = minOf(1000L, (90L * 86_400_000L - 1L) / interval + 1L)
        require(slotsPerWindow > 0L) { "Unsupported cTrader history period" }
        // Continuous windows preserve broker bars shifted off fixed UTC boundaries.
        val maxWindowSpan = minOf(90L * 86_400_000L - 1L, slotsPerWindow * interval - 1L)
        val results = ArrayList<T>()
        var windowStart = from
        while (windowStart <= to) {
            val windowEnd = windowStart + minOf(maxWindowSpan, to - windowStart)
            var cursorEnd = windowEnd
            while (cursorEnd >= windowStart) {
                // Allow a shifted broker-open bar without exceeding 1000 bars.
                val count = minOf(1000L, (cursorEnd - windowStart) / interval + 2L).toInt()
                var page = fetch(windowStart, cursorEnd, count)
                if (page.hasMore && page.items.isEmpty() && count < 1000) {
                    // A broker may mark a sparse closed-market range as having
                    // more older records. Probe once at the maximum count before
                    // treating this particular window as containing no bars.
                    page = fetch(windowStart, cursorEnd, 1000)
                }
                val ordered = page.items.sortedBy(timeOf)
                var previous = Long.MIN_VALUE
                for (item in ordered) {
                    val opened = timeOf(item)
                    require(opened in windowStart..cursorEnd) {
                        "cTrader candle outside requested page"
                    }
                    require(opened > previous) { "Duplicate cTrader history candle" }
                    previous = opened
                    results.add(item)
                }

                if (!page.hasMore) break
                if (ordered.isEmpty()) {
                    // No actual candle timestamp exists to continue backwards.
                    // Keep other verified windows usable instead of failing the
                    // whole chart. No blank timeframe is filled with fake bars.
                    break
                }
                val oldest = timeOf(ordered.first())
                if (oldest <= windowStart) break
                // The next request must include every timestamp before oldest.
                val nextEnd = oldest - 1L
                require(nextEnd < cursorEnd) { "Non-advancing cTrader history page" }
                cursorEnd = nextEnd
            }
            windowStart = windowEnd + 1L
        }
        return results.sortedBy(timeOf)
    }
}
