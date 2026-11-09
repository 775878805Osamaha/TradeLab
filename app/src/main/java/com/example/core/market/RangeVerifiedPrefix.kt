package com.example.core.market

/**
 * Reusing a previous Range scan is safe only if EVERY already-processed BID
 * quote is the identical verified object in the same order, with nothing
 * removed from the beginning. Comparing timestamps, prices, or just the
 * endpoints could silently mix amended broker data or same-ms quote events.
 *
 * This is a reference-only scan: it skips the price conversion, range maths,
 * diagnostics and candle allocations of a full rebuild.
 */
object RangeVerifiedPrefix {
    fun reusableQuoteCount(
        previous: List<RangePriceTick>, current: List<RangePriceTick>,
        cancellationCheckpoint: () -> Unit = {}
    ): Int {
        if (previous.isEmpty() || previous.size > current.size) return 0
        for (index in previous.indices) {
            if ((index and 16383) == 0) cancellationCheckpoint()
            if (previous[index] !== current[index]) return 0
        }
        return previous.size
    }
}
