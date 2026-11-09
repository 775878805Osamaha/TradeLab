package com.example.feature.chart.model

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class RangeReplayLoadQueueTest {
    @Test fun advancingReplayNeverCancelsVerifiedInFlightTickHistory() = runBlocking {
        val cutoffs = MutableStateFlow<Long?>(null)
        val started = Channel<Long>(Channel.UNLIMITED)
        val releaseFirst = CompletableDeferred<Unit>()
        val completed = mutableListOf<Long>()
        val worker = launch(start = CoroutineStart.UNDISPATCHED) {
            RangeReplayLoadQueue.consume(cutoffs) { cutoff ->
                started.send(cutoff)
                if (cutoff == 100L) releaseFirst.await()
                completed.add(cutoff)
            }
        }
        try {
            cutoffs.value = 100L
            assertEquals(100L, withTimeout(2_000L) { started.receive() })
            // Two consecutive M15 replay reveals happen before the broker's
            // current BID quote page returns. Neither should cancel it.
            cutoffs.value = 200L
            cutoffs.value = 300L
            releaseFirst.complete(Unit)
            assertEquals(300L, withTimeout(2_000L) { started.receive() })
            assertEquals(listOf(100L, 300L), completed)
            assertFalse(worker.isCancelled)
        } finally { worker.cancelAndJoin() }
    }

    @Test fun sameDatasetMayKeepCompletedOlderReplayBarsButNeverFutureQuotes() {
        fun show(loaded: Long, revealed: Long, complete: Boolean = true,
                 sameDataset: Boolean = true) = RangeReplayVisibilityPolicy.canShow(
            loaded, revealed, replay = true, complete = complete,
            loading = true, sameDataset = sameDataset)
        assertTrue(show(1_000L, 1_000L))
        assertTrue(show(1_000L, 2_000L))
        assertFalse(show(2_000L, 1_000L))
        assertFalse(show(1_000L, 2_000L, complete = false))
        assertFalse(show(1_000L, 2_000L, sameDataset = false))
        assertFalse(RangeReplayVisibilityPolicy.canShow(1_000L, null, true, true, true, true))
    }

    @Test fun liveChartStillRequiresMatchingCutoffExceptWhileLoading() {
        assertTrue(RangeReplayVisibilityPolicy.canShow(1_000L, 2_000L,
            replay = false, complete = true, loading = true, sameDataset = true))
        assertFalse(RangeReplayVisibilityPolicy.canShow(1_000L, 2_000L,
            replay = false, complete = true, loading = false, sameDataset = true))
        assertTrue(RangeReplayVisibilityPolicy.canShow(2_000L, 2_000L,
            replay = false, complete = false, loading = false, sameDataset = true))
        // A manual backwards jump must not show a newer broker window while loading.
        assertFalse(RangeReplayVisibilityPolicy.canShow(3_000L, 2_000L,
            replay = false, complete = true, loading = true, sameDataset = true))
        assertFalse(RangeReplayVisibilityPolicy.canShow(1_000L, 2_000L,
            replay = false, complete = false, loading = true, sameDataset = true))
    }
}
