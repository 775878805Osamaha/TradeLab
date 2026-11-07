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
}
