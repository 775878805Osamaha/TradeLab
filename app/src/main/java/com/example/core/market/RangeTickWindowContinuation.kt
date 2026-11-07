package com.example.core.market

/**
 * Downloads ONLY older history absent from a previously complete chart window.
 * Each verified newest-first sub-page survives a cancelled pan/backfill; when
 * resumed, the exact contiguous BID suffix is reused without timestamp overlap.
 * The cache is broker-account scoped and never mixes Replay cutoffs.
 */
object RangeTickWindowContinuation {
    suspend fun downloadOlder(
        from: Long,
        to: Long,
        symbol: String,
        source: String,
        cache: RangeTickSuffixCache,
        onProgress: suspend (Int, Int) -> Unit = { _, _ -> },
        maxQuotes: Int = RangeTickBatchLoader.MAX_WINDOW_TICKS,
        request: suspend (Long, Long) -> List<RangePriceTick>
    ): List<RangePriceTick> {
        require(from > 0L && to >= from && to - from <= 604_800_000L)
        require(maxQuotes in 1..RangeTickBatchLoader.MAX_WINDOW_TICKS)
        val verified = cache.snapshot(symbol, source, from, to)
        val savedCount = verified?.ticks?.size ?: 0
        val lastUnfetched = verified?.from?.minus(1L) ?: to
        if (savedCount > maxQuotes || (savedCount == maxQuotes && lastUnfetched >= from))
            throw RangeTickHistoryTooDenseException(
                "عدد بيانات Tick أكبر من ذاكرة العرض؛ استعرض فترة أقصر")
        if (verified != null) onProgress(savedCount, 0)
        val older = if (lastUnfetched >= from) {
            RangeTickBatchLoader.load(from, lastUnfetched,
                onSliceComplete = { count, pages -> onProgress(savedCount + count, pages) },
                onVerifiedSlice = { start, end, quotes ->
                    cache.remember(symbol, source, start, end, quotes)
                }, maxAllowedTicks = maxQuotes - savedCount, request = request)
        } else emptyList()
        return if (verified == null) older else ArrayList<RangePriceTick>(older.size + savedCount).apply {
            addAll(older)
            addAll(verified.ticks)
        }
    }
}
