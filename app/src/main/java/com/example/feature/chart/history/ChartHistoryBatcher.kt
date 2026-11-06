package com.example.feature.chart.history

import com.example.core.model.Candle

/**
 * Buffers a few verified, progressively older pages before one UI merge.
 * The download cursor stays in ChartHistoryDownload, so batching never
 * changes provider requests, candle prices, or the replay visibility limit.
 *
 * Keep pending pages until the caller confirms its merge was published:
 * cancellation during a merge can then retry the pending real candles.
 */
class ChartHistoryBatcher(private val pageLimit: Int = 5) {
    init { require(pageLimit > 0) }

    private val pages = ArrayList<List<Candle>>(pageLimit)

    val pendingPages: Int get() = pages.size
    val shouldFlush: Boolean get() = pages.size >= pageLimit

    fun stage(page: List<Candle>) {
        require(page.isNotEmpty()) { "Cannot stage an empty historical page" }
        require(page.zipWithNext().all { (a, b) -> a.openTime < b.openTime }) {
            "Historical pages must be strictly chronological"
        }
        if (pages.isNotEmpty()) {
            require(page.last().openTime < pages.last().first().openTime) {
                "Historical page must be strictly older than the pending cursor"
            }
        }
        pages.add(page)
    }

    /** A chronological snapshot, oldest first. Does not acknowledge/clear. */
    fun snapshot(): List<Candle> {
        if (pages.isEmpty()) return emptyList()
        val result = ArrayList<Candle>(pages.sumOf { it.size })
        for (i in pages.indices.reversed()) result.addAll(pages[i])
        return result
    }

    /** Called only after the state repository has accepted the snapshot. */
    fun committed() { pages.clear() }
}
