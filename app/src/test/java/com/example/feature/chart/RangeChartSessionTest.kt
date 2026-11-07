package com.example.feature.chart

import com.example.core.market.RangeTickDiagnostics
import org.junit.Assert.*
import org.junit.Test

class RangeChartSessionTest {
    private val gold = RangeChartContext("XAUUSD", 1000, 7L, false, 0L)

    private fun snapshot(context: RangeChartContext = gold, end: Long = 100_000L,
                         hours: Int = 6, generation: Int = 0, complete: Boolean = true) =
        RangeChartSnapshot(context.symbol, end, context.size, hours,
            context.accountGeneration, context.replay, context.replayDatasetId,
            emptyList(), RangeTickDiagnostics(), complete, generation)

    @Test fun returningFromAnotherTabKeepsTheExactBrokerCutoffAndCompletedBars() {
        val session = RangeChartSession()
        assertTrue(session.alignTo(gold, now = 100_000L))
        val completed = snapshot()
        session.snapshot.value = completed
        session.historyHours.intValue = 6
        session.refreshAnchor.longValue = completed.end
        session.historyManuallyChosen.value = true

        // ChartScreen was destroyed and composed again. ViewModel was not.
        assertFalse(session.alignTo(gold, now = 200_000L))
        assertSame(completed, session.snapshot.value)
        assertEquals(100_000L, session.refreshAnchor.longValue)
        assertEquals(6, session.historyHours.intValue)
        assertTrue(session.historyManuallyChosen.value)
        assertTrue(RangeChartRestorationPolicy.canSkipDownload(
            session.snapshot.value, gold, 100_000L, 6, 0))
    }

    @Test fun anExplicitRefreshMustDownloadEvenIfItsMillisecondCutoffIsUnchanged() {
        assertTrue(RangeChartRestorationPolicy.canSkipDownload(snapshot(), gold, 100_000L, 6, 0))
        assertFalse(RangeChartRestorationPolicy.canSkipDownload(snapshot(), gold, 100_000L, 6, 1))
        assertFalse(RangeChartRestorationPolicy.canSkipDownload(snapshot(complete = false), gold, 100_000L, 6, 0))
        assertFalse(RangeChartRestorationPolicy.canSkipDownload(snapshot(), gold, 100_001L, 6, 0))
        assertFalse(RangeChartRestorationPolicy.canSkipDownload(snapshot(), gold, 100_000L, 12, 0))
    }

    @Test fun accountSymbolRangeSizeAndReplayDatasetChangesInvalidatePriorCandles() {
        val session = RangeChartSession()
        session.alignTo(gold, 100_000L)
        session.snapshot.value = snapshot()
        val changes = listOf(
            gold.copy(accountGeneration = 8L),
            gold.copy(symbol = "EURUSD"),
            gold.copy(size = 100),
            gold.copy(replay = true, replayDatasetId = 123L)
        )
        for (changed in changes) {
            assertFalse(RangeChartRestorationPolicy.canSkipDownload(snapshot(),
                changed, 100_000L, 6, 0))
            assertTrue(session.alignTo(changed, 200_000L))
            assertNull(session.snapshot.value)
            assertEquals(200_000L, session.refreshAnchor.longValue)
            assertFalse(session.loading.value)
            session.alignTo(gold, 100_000L)
            session.snapshot.value = snapshot()
        }
    }

    @Test fun replayNeverReusesBarsFromAFutureOrAnotherReplayDataset() {
        val replay = gold.copy(replay = true, replayDatasetId = 41L)
        val completed = snapshot(replay, end = 100_000L)
        assertTrue(RangeChartRestorationPolicy.canSkipDownload(completed, replay, 100_000L, 6, 0))
        assertFalse(RangeChartRestorationPolicy.canSkipDownload(completed, replay, 99_000L, 6, 0))
        assertFalse(RangeChartRestorationPolicy.canSkipDownload(completed,
            replay.copy(replayDatasetId = 42L), 100_000L, 6, 0))
    }

    @Test fun leavingAndReturningWhileDownloadIsActiveDoesNotStartItAgain() {
        val queue = RangeChartRequestQueue()
        val first = RangeChartLoadRequest(gold, 100_000L, 6, 0)
        assertTrue(queue.offer(first))
        // ChartScreen was disposed, then reentered before the broker replied.
        assertFalse(queue.offer(first))
        assertEquals(first, queue.active)
        assertNull(queue.pending)
        assertNull(queue.finish(first))
        assertNull(queue.active)
        assertTrue(queue.offer(first)) // retry remains possible after a failed download
    }

    @Test fun replayKeepsActiveBrokerDownloadAndOnlyQueuesNewestRevealedCutoff() {
        val queue = RangeChartRequestQueue()
        val replay = gold.copy(replay = true, replayDatasetId = 22L)
        val first = RangeChartLoadRequest(replay, 100_000L, 6, 0)
        val middle = first.copy(cutoff = 200_000L)
        val latest = first.copy(cutoff = 300_000L)
        assertTrue(queue.offer(first))
        assertFalse(queue.offer(middle))
        assertFalse(queue.offer(latest))
        assertFalse(queue.offer(latest))
        assertEquals(first, queue.active)
        assertEquals(latest, queue.pending)
        assertEquals(latest, queue.finish(first))
        assertEquals(latest, queue.active)
        assertNull(queue.finish(latest))
    }

    @Test fun switchingCTraderAccountsInvalidatesInFlightAndQueuedRequests() {
        val queue = RangeChartRequestQueue()
        val first = RangeChartLoadRequest(gold, 100_000L, 6, 0)
        queue.offer(first)
        queue.offer(first.copy(cutoff = 200_000L))
        queue.invalidate()
        val newAccount = first.copy(context = gold.copy(accountGeneration = 8L))
        assertTrue(queue.offer(newAccount))
        assertNull(queue.finish(first)) // old cancelled job cannot consume new account work
        assertEquals(newAccount, queue.active)
        assertNull(queue.pending)
    }

    @Test fun replayRewindToActiveCutoffDiscardsPreviouslyQueuedFutureCutoff() {
        val queue = RangeChartRequestQueue()
        val replay = gold.copy(replay = true, replayDatasetId = 22L)
        val earlier = RangeChartLoadRequest(replay, 100_000L, 6, 0)
        queue.offer(earlier)
        queue.offer(earlier.copy(cutoff = 200_000L))
        assertFalse(queue.offer(earlier))
        assertNull(queue.pending)
        assertNull(queue.finish(earlier))
    }

    @Test fun rangeViewportPreservesUserZoomAndPanOnTabReturn() {
        val session = RangeChartSession()
        session.alignTo(gold, 100_000L)
        session.viewport.candleWidthPx.floatValue = 19f
        session.viewport.scrollOffsetPx.floatValue = 420f
        session.viewport.manualPriceScale.floatValue = 1.8f
        session.viewport.pricePanPx.floatValue = -75f
        session.viewport.initialFitApplied.value = true
        session.viewport.fittedDisplayStyle.value = com.example.ui.components.ChartDisplayStyle.RANGE
        session.viewport.lastBackfillOldestTime.value = 50_000L
        session.viewport.lastBackfillScrollOffset.floatValue = 400f

        assertFalse(session.alignTo(gold, 200_000L))
        assertEquals(19f, session.viewport.candleWidthPx.floatValue, 0f)
        assertEquals(420f, session.viewport.scrollOffsetPx.floatValue, 0f)
        assertEquals(1.8f, session.viewport.manualPriceScale.floatValue, 0f)
        assertEquals(-75f, session.viewport.pricePanPx.floatValue, 0f)
        assertTrue(session.viewport.initialFitApplied.value)
        assertEquals(50_000L, session.viewport.lastBackfillOldestTime.value)
        assertEquals(400f, session.viewport.lastBackfillScrollOffset.floatValue, 0f)

        // A different instrument is a real new viewport, unlike a tab switch.
        assertTrue(session.alignTo(gold.copy(symbol = "EURUSD"), 200_000L))
        assertEquals(12f, session.viewport.candleWidthPx.floatValue, 0f)
        assertEquals(0f, session.viewport.scrollOffsetPx.floatValue, 0f)
        assertEquals(1f, session.viewport.manualPriceScale.floatValue, 0f)
        assertEquals(0f, session.viewport.pricePanPx.floatValue, 0f)
        assertFalse(session.viewport.initialFitApplied.value)
        assertNull(session.viewport.lastBackfillOldestTime.value)
        assertEquals(0f, session.viewport.lastBackfillScrollOffset.floatValue, 0f)
    }
}
