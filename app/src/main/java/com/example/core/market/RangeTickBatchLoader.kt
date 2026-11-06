package com.example.core.market

/**
 * Loads genuine broker BID ticks chronologically in small, contiguous requests.
 * A dense broker response is retried with smaller time slices; malformed or
 * unavailable data is never replaced with synthetic prices.
 */
object RangeTickBatchLoader {
    const val MAX_WINDOW_TICKS = 1_000_000
    private const val MAX_REQUEST_MILLIS = 6L * 3_600_000L
    private const val MAX_SPLIT_DEPTH = 8

    suspend fun load(from: Long, to: Long,
                     request: suspend (Long, Long) -> List<RangePriceTick>): List<RangePriceTick> {
        require(from > 0L && to >= from && to - from <= 604_800_000L)

        suspend fun fetchSlice(start: Long, end: Long, depth: Int): List<RangePriceTick> {
            val page = try {
                request(start, end)
            } catch (dense: RangeTickHistoryTooDenseException) {
                if (start == end || depth >= MAX_SPLIT_DEPTH) throw dense
                val middle = start + (end - start) / 2L
                return fetchSlice(start, middle, depth + 1) +
                    fetchSlice(middle + 1L, end, depth + 1)
            }
            var previous = start
            for (tick in page) {
                require(tick.timestamp in start..end && tick.timestamp >= previous &&
                    tick.price.isFinite() && tick.price > 0.0) {
                    "Invalid ordered cTrader tick page"
                }
                previous = tick.timestamp
            }
            return page
        }

        val result = ArrayList<RangePriceTick>()
        var cursor = from
        while (cursor <= to) {
            val end = minOf(to, cursor + MAX_REQUEST_MILLIS - 1L)
            val page = fetchSlice(cursor, end, 0)
            if (result.size.toLong() + page.size > MAX_WINDOW_TICKS)
                throw RangeTickHistoryTooDenseException(
                    "عدد بيانات Tick أكبر من ذاكرة العرض؛ استعرض فترة أقصر")
            result.addAll(page)
            cursor = end + 1L
        }
        return result
    }
}
