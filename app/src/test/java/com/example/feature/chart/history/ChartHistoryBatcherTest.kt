package com.example.feature.chart.history

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class ChartHistoryBatcherTest {
    private fun bar(at: Long) = Candle(
        symbol = "XAUUSD", timeframe = Timeframe.M1, openTime = at,
        closeTime = at + 60_000L, open = 100.0, high = 102.0,
        low = 99.0, close = 101.0, volume = 1.0, source = "TEST_FIXTURE"
    )

    @Test fun batchingMoreThan100000BarsPublishesOnlyEveryFiveRealPages() {
        val batcher = ChartHistoryBatcher(pageLimit = 5)
        var candles = listOf(bar(120_000L * 60_000L))
        var commits = 0
        repeat(201) {
            val oldest = 120_000L - (it + 1L) * 500L
            val verifiedPage = List(500) { i -> bar((oldest + i) * 60_000L) }
            batcher.stage(verifiedPage)
            if (batcher.shouldFlush) {
                candles = ChartHistoryPaging.merge(candles, batcher.snapshot())
                batcher.committed()
                commits++
            }
        }
        assertEquals(1, batcher.pendingPages)
        candles = ChartHistoryPaging.merge(candles, batcher.snapshot())
        batcher.committed()
        commits++
        assertEquals(41, commits) // Instead of 201 full 100k-list merges.
        assertEquals(100_501, candles.size)
        assertTrue(candles.zipWithNext().all { (a, b) -> a.openTime < b.openTime })
        assertEquals(0, batcher.pendingPages)
    }

    @Test fun cancellationBeforePublishLeavesPendingPagesReadyToRetry() {
        val batcher = ChartHistoryBatcher(pageLimit = 5)
        batcher.stage(listOf(bar(480_000L), bar(540_000L)))
        batcher.stage(listOf(bar(360_000L), bar(420_000L)))
        assertFalse(batcher.shouldFlush)
        val beforeCancellation = batcher.snapshot()
        assertEquals(listOf(360_000L, 420_000L, 480_000L, 540_000L),
            beforeCancellation.map { it.openTime })
        // A cancelled merge never acknowledges the staged real pages.
        assertEquals(2, batcher.pendingPages)
        assertEquals(beforeCancellation, batcher.snapshot())
        batcher.committed()
        assertTrue(batcher.snapshot().isEmpty())
    }

    @Test fun rejectsNonAdvancingOrMisorderedProviderPages() {
        val batcher = ChartHistoryBatcher()
        batcher.stage(listOf(bar(300_000L), bar(360_000L)))
        for (invalid in listOf(
            emptyList(),
            listOf(bar(240_000L), bar(240_000L)),
            listOf(bar(360_000L)),
            listOf(bar(420_000L))
        )) {
            try {
                batcher.stage(invalid)
                fail("Invalid provider page should not be staged")
            } catch (_: IllegalArgumentException) { }
        }
        assertEquals(1, batcher.pendingPages)
    }
}
