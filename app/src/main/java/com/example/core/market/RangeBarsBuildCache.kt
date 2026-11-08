package com.example.core.market

import java.util.ArrayDeque

/** Small single-window memo for expensive genuine-tick Range reconstruction.
 * Tick-list reference identity is intentional: a new historical window must
 * NEVER inherit bars calculated from an earlier quote sequence. */
class RangeBarsBuildCache(private val capacity: Int = 2) {
    init { require(capacity in 1..4) }

    private data class Entry(
        val ticks: List<RangePriceTick>,
        val symbol: String, val source: String, val tickSize: Double,
        val rangeSize: Int, val incomplete: Boolean, val result: VerifiedRangeBars
    )
    private val entries = ArrayDeque<Entry>()

    @Synchronized fun clear() { entries.clear() }

    @Synchronized fun find(ticks: List<RangePriceTick>, symbol: String, source: String,
                           tickSize: Double, size: Int, incomplete: Boolean): VerifiedRangeBars? =
        entries.firstOrNull { it.ticks === ticks && it.symbol == symbol &&
            it.source == source && it.tickSize == tickSize &&
            it.rangeSize == size && it.incomplete == incomplete }?.result

    @Synchronized fun remember(ticks: List<RangePriceTick>, symbol: String, source: String,
                                tickSize: Double, size: Int, incomplete: Boolean,
                                result: VerifiedRangeBars) {
        // Do not keep separate million-quote windows alive in memory.
        if (entries.firstOrNull()?.ticks !== ticks) entries.clear()
        val duplicate = entries.firstOrNull { it.symbol == symbol && it.source == source &&
            it.tickSize == tickSize && it.rangeSize == size && it.incomplete == incomplete }
        if (duplicate != null) entries.remove(duplicate)
        entries.addFirst(Entry(ticks, symbol, source, tickSize, size, incomplete, result))
        while (entries.size > capacity) entries.removeLast()
    }
}
