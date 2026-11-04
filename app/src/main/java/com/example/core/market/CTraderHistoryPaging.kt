package com.example.core.market

import java.io.IOException

internal object CTraderHistoryPaging {
    data class Page<T>(val items: List<T>, val hasMore: Boolean)

    suspend fun <T> load(
        from: Long,
        to: Long,
        interval: Long,
        fetch: suspend (start: Long, end: Long, count: Int) -> Page<T>,
    ): List<T> {
        // Reserve one millisecond for the upper bound sent to the broker.
        val slotsPerPage = minOf(1000L, (90L * 86_400_000L - 1L) / interval + 1L)
        val result = ArrayList<T>()

        suspend fun read(start: Long, slots: Long) {
            val end = start + (slots - 1L) * interval
            val page = fetch(start, end, slots.toInt())
            if (!page.hasMore) {
                result.addAll(page.items)
                return
            }
            if (slots == 1L) throw IOException("cTrader returned incomplete history for one candle")
            val firstHalf = slots / 2L
            read(start, firstHalf)
            read(start + firstHalf * interval, slots - firstHalf)
        }

        var start = from
        while (start <= to) {
            val slots = minOf(slotsPerPage, (to - start) / interval + 1L)
            read(start, slots)
            start += slots * interval
        }
        return result
    }
}
