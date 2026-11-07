package com.example.core.market

import java.util.ArrayDeque

/** Reuses only fully verified, contiguous historical BID slices after a
 * cancelled newest-first download. Endpoints are inclusive. Empty broker
 * periods are retained too, so no unverified time gap can enter the result.
 * The bounded memory cap deliberately favors recent quotes on older phones.
 */
class RangeTickSuffixCache(private val maxTicks: Int = 200_000) {
    init { require(maxTicks > 0) }

    data class Snapshot(val from: Long, val to: Long, val ticks: List<RangePriceTick>)
    private data class Slice(val from: Long, val to: Long, val ticks: List<RangePriceTick>)
    private val newestFirst = ArrayDeque<Slice>()
    private var symbol: String? = null
    private var source: String? = null
    private var start = 0L
    private var end = 0L
    private var tickCount = 0

    @Synchronized fun clear() {
        newestFirst.clear(); symbol = null; source = null
        start = 0L; end = 0L; tickCount = 0
    }

    @Synchronized fun remember(symbol: String, source: String,
                               from: Long, to: Long, quotes: List<RangePriceTick>) {
        require(symbol.isNotBlank() && source.startsWith("ctrader:"))
        require(from > 0L && to >= from)
        var preceding = from
        for (quote in quotes) {
            require(quote.timestamp in from..to && quote.timestamp >= preceding &&
                quote.price.isFinite() && quote.price > 0.0) { "Invalid verified range slice" }
            preceding = quote.timestamp
        }
        if (quotes.size > maxTicks) { clear(); return }
        if (this.symbol != symbol || this.source != source ||
            newestFirst.isEmpty() || end != to && start - 1L != to) {
            clear()
            this.symbol = symbol; this.source = source
            start = from; end = to
            newestFirst.add(Slice(from, to, quotes))
            tickCount = quotes.size
            return
        }
        // Only an OLDER contiguous slice extends the covered suffix. A
        // repeated or overlapping timestamp range is not silently merged.
        if (start - 1L != to) { clear(); return }
        newestFirst.addLast(Slice(from, to, quotes))
        start = from
        tickCount += quotes.size
        // Drop the oldest full slices when memory is saturated, preserving a
        // genuinely contiguous newest suffix ending at the original cutoff.
        while (tickCount > maxTicks && newestFirst.size > 1) {
            val removed = newestFirst.removeLast()
            tickCount -= removed.ticks.size
            start = newestFirst.peekLast().from
        }
    }

    @Synchronized fun snapshot(symbol: String, source: String,
                               from: Long, to: Long): Snapshot? {
        if (this.symbol != symbol || this.source != source ||
            newestFirst.isEmpty() || end != to || start > to || from > to) return null
        val collected = ArrayList<RangePriceTick>(tickCount)
        val chronological = newestFirst.descendingIterator()
        while (chronological.hasNext()) collected.addAll(chronological.next().ticks)
        if (from > start) collected.removeAll { it.timestamp < from }
        return Snapshot(maxOf(from, start), end, collected)
    }
}
