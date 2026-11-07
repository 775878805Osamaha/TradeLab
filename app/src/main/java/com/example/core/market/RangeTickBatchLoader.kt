package com.example.core.market

import kotlinx.coroutines.delay

/**
 * Loads genuine broker BID ticks chronologically in small, contiguous requests.
 * A dense broker response is retried with smaller time slices; malformed or
 * unavailable data is never replaced with synthetic prices.
 */
object RangeTickBatchLoader {
    const val MAX_WINDOW_TICKS = 1_000_000
    private const val HOUR_MILLIS = 3_600_000L
    private const val MAX_REQUEST_MILLIS = 6L * HOUR_MILLIS
    private const val MIN_REQUEST_MILLIS = 60_000L
    private const val TARGET_TICKS_PER_SLICE = 50_000L
    private const val MAX_SPLIT_DEPTH = 12

    /** Dense gold markets can overflow even a one-hour broker response.
     * Compute the next period from the actual number of verified quotes,
     * down to one minute, rather than repeatedly splitting full hours.
     * The 50k target is a request-size budget, NOT a fabricated tick count.
     */
    internal fun nextSliceMillis(tickCount: Int, measuredMillis: Long): Long {
        require(tickCount >= 0 && measuredMillis > 0L)
        if (tickCount == 0) return MAX_REQUEST_MILLIS
        return (TARGET_TICKS_PER_SLICE * measuredMillis / tickCount)
            .coerceIn(MIN_REQUEST_MILLIS, MAX_REQUEST_MILLIS)
    }

    private suspend fun requestWithRetry(start: Long, end: Long,
                                          request: suspend (Long, Long) -> List<RangePriceTick>): List<RangePriceTick> {
        var transientFailures = 0
        while (true) {
            try {
                return request(start, end)
            } catch (error: CTraderGatewayException) {
                // Only transient HTTP states are retried. Invalid prices,
                // account permissions and malformed history must fail closed.
                if (error.statusCode !in setOf(429, 500, 502, 503, 504) || transientFailures >= 2)
                    throw error
                delay(if (error.statusCode == 429) 1_000L else 250L * (transientFailures + 1L))
                transientFailures++
            }
        }
    }

    suspend fun load(from: Long, to: Long,
                     onNewestSlice: suspend (List<RangePriceTick>) -> Unit = {},
                     onSliceComplete: suspend (Int, Int) -> Unit = { _, _ -> },
                     onVerifiedSlice: suspend (Long, Long, List<RangePriceTick>) -> Unit = { _, _, _ -> },
                     maxAllowedTicks: Int = MAX_WINDOW_TICKS,
                     request: suspend (Long, Long) -> List<RangePriceTick>): List<RangePriceTick> {
        require(from > 0L && to >= from && to - from <= 604_800_000L)
        require(maxAllowedTicks in 1..MAX_WINDOW_TICKS)
        var previewSent = false
        var count = 0
        var completeSlices = 0
        // Keep each real broker leaf exactly once, newest-first. The former
        // recursive `oldest + newest` copied the same quote references again
        // at EACH bisection level (O(n * splitDepth) list merging).
        val descendingSlices = ArrayList<List<RangePriceTick>>()

        suspend fun fetchSlice(start: Long, end: Long, depth: Int) {
            val page = try {
                requestWithRetry(start, end, request)
            } catch (dense: RangeTickHistoryTooDenseException) {
                if (start == end || depth >= MAX_SPLIT_DEPTH) throw dense
                val middle = start + (end - start) / 2L
                // Even for dense windows request the newest half first.
                fetchSlice(middle + 1L, end, depth + 1)
                fetchSlice(start, middle, depth + 1)
                return
            }
            var previous = start
            for (tick in page) {
                require(tick.timestamp in start..end && tick.timestamp >= previous &&
                    tick.price.isFinite() && tick.price > 0.0) {
                    "Invalid ordered cTrader tick page"
                }
                previous = tick.timestamp
            }
            // Enforce the memory limit before any split parent can concatenate
            // large child arrays, and count only fully received broker leaves.
            if (count.toLong() + page.size > maxAllowedTicks)
                throw RangeTickHistoryTooDenseException(
                    "عدد بيانات Tick أكبر من ذاكرة العرض؛ استعرض فترة أقصر")
            // Notify ONLY verified, complete leaves, including smaller leaves
            // returned after a hasMore split. If an older sibling is cancelled
            // later, these newest leaves can still be safely reused.
            onVerifiedSlice(start, end, page)
            descendingSlices.add(page)
            count += page.size
            completeSlices++
            onSliceComplete(count, completeSlices)
            if (!previewSent && page.isNotEmpty()) {
                previewSent = true
                onNewestSlice(page)
            }
        }

        // Load the visible, most recent chart first. The final response is
        // still strictly chronological and includes all genuine broker ticks.
        var cursor = to
        var requestMillis = HOUR_MILLIS
        while (cursor >= from) {
            // Both endpoints are inclusive. If exactly one hour remains,
            // consume its first millisecond in this request instead of
            // incurring an additional HTTP call for a single quote timestamp.
            val start = if (cursor - from <= requestMillis) from
                else cursor - requestMillis + 1L
            val before = count
            fetchSlice(start, cursor, 0)
            requestMillis = nextSliceMillis(count - before, cursor - start + 1L)
            cursor = start - 1L
        }
        val result = ArrayList<RangePriceTick>(count)
        for (slice in descendingSlices.asReversed()) result.addAll(slice)
        return result
    }
}
