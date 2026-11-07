package com.example.core.market

/** Selects a precise inclusive view of already verified, sorted BID quotes
 * using two binary searches, without allocating or copying a million-entry
 * reference array on every Replay step / historical pan. Source lists are
 * treated as immutable once verified; no caller modifies the backing array.
 * A smaller request must never expose future or past quotes in Replay.
 */
object RangeTickWindowReuse {
    fun between(ticks: List<RangePriceTick>, from: Long, to: Long): List<RangePriceTick> {
        require(from > 0L && to >= from)
        var left = 0
        var right = ticks.size
        while (left < right) {
            val middle = (left + right) ushr 1
            if (ticks[middle].timestamp < from) left = middle + 1 else right = middle
        }
        val first = left
        right = ticks.size
        while (left < right) {
            val middle = (left + right) ushr 1
            if (ticks[middle].timestamp <= to) left = middle + 1 else right = middle
        }
        val afterLast = left
        return if (first == 0 && afterLast == ticks.size) ticks
            else ticks.subList(first, afterLast)
    }
}
