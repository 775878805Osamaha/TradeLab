package com.example.core.market

import java.io.IOException

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
        val results = ArrayList<T>()
        var windowStart = from
        while (windowStart <= to) {
            val slots = minOf(slotsPerWindow, (to - windowStart) / interval + 1L)
            val windowEnd = windowStart + (slots - 1L) * interval
            var cursorEnd = windowEnd
            while (cursorEnd >= windowStart) {
                val count = ((cursorEnd - windowStart) / interval + 1L).toInt()
                val page = fetch(windowStart, cursorEnd, count)
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
                    // The broker claimed more records but provided no cursor:
                    // a retry cannot advance safely without fabricating bars.
                    throw IOException("cTrader returned a truncated empty history page")
                }
                val oldest = timeOf(ordered.first())
                if (oldest <= windowStart) break
                val nextEnd = oldest - interval
                require(nextEnd < cursorEnd) { "Non-advancing cTrader history page" }
                cursorEnd = nextEnd
            }
            windowStart = windowEnd + interval
        }
        return results.sortedBy(timeOf)
    }
}
