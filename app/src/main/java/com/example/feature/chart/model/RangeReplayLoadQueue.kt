package com.example.feature.chart.model

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.collect

/**
 * A Replay cursor can advance faster than cTrader can download BID history.
 * Finish the in-flight read instead of cancelling every time a candle is
 * revealed, then catch up to the newest requested cutoff. A changed dataset,
 * broker, symbol or Range size cancels the owning coroutine separately.
 */
object RangeReplayLoadQueue {
    suspend fun consume(cutoffs: Flow<Long?>, load: suspend (Long) -> Unit) {
        cutoffs.filterNotNull().conflate().collect { cutoff -> load(cutoff) }
    }
}

/** One previously completed Replay window is safe to show only when it is
 * from the SAME training dataset and no later than its currently revealed
 * cutoff. Unfinished previews from an older cursor are never reused.
 */
object RangeReplayVisibilityPolicy {
    fun canShow(snapshotEnd: Long, currentEnd: Long?, replay: Boolean,
                complete: Boolean, loading: Boolean, sameDataset: Boolean): Boolean {
        if (currentEnd == null || !sameDataset) return false
        // During a backwards historical jump an old live snapshot may end
        // AFTER the requested cutoff. Never paint that future window merely
        // because the replacement is still loading.
        if (!replay) return snapshotEnd == currentEnd ||
            (complete && loading && snapshotEnd < currentEnd)
        return snapshotEnd == currentEnd || (complete && snapshotEnd < currentEnd)
    }
}
