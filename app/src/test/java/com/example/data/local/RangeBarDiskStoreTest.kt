package com.example.data.local

import com.example.core.market.RangeTickDiagnostics
import com.example.core.market.VerifiedRangeBars
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class RangeBarDiskStoreTest {
    private val source = "ctrader:demo:7:12"
    private val gold = "XAUUSD"

    private class FakeDao : RangeBarSnapshotDao {
        val rows = mutableListOf<RangeBarSnapshotEntity>()
        override suspend fun exact(source: String, symbol: String, from: Long, to: Long,
                                   size: Int, tickSizeBits: Long,
                                   includeIncomplete: Boolean): RangeBarSnapshotEntity? =
            rows.firstOrNull { it.source == source && it.symbol == symbol &&
                it.fromMillis == from && it.toMillis == to && it.rangeTicks == size &&
                it.tickSizeBits == tickSizeBits && it.includeIncomplete == includeIncomplete }

        override suspend fun latest(source: String, symbol: String, size: Int,
                                    tickSizeBits: Long, includeIncomplete: Boolean,
                                    minimumTo: Long, requestedTo: Long): List<RangeBarSnapshotEntity> =
            rows.filter { it.source == source && it.symbol == symbol && it.rangeTicks == size &&
                it.tickSizeBits == tickSizeBits && it.includeIncomplete == includeIncomplete &&
                it.toMillis in minimumTo..requestedTo }.sortedByDescending { it.toMillis }.take(4)

        override suspend fun save(snapshot: RangeBarSnapshotEntity) {
            rows.removeAll { it.source == snapshot.source && it.symbol == snapshot.symbol &&
                it.fromMillis == snapshot.fromMillis && it.toMillis == snapshot.toMillis &&
                it.rangeTicks == snapshot.rangeTicks && it.tickSizeBits == snapshot.tickSizeBits &&
                it.includeIncomplete == snapshot.includeIncomplete }
            rows += snapshot
        }

        override suspend fun discard(source: String, symbol: String, from: Long, to: Long,
                                     size: Int, tickSizeBits: Long, includeIncomplete: Boolean) {
            rows.removeAll { it.source == source && it.symbol == symbol &&
                it.fromMillis == from && it.toMillis == to && it.rangeTicks == size &&
                it.tickSizeBits == tickSizeBits && it.includeIncomplete == includeIncomplete }
        }
    }

    private fun result(openTime: Long, end: Long) = VerifiedRangeBars(
        listOf(Candle(gold, Timeframe.M1, openTime, end, 4070.0, 4080.0,
            4065.0, 4075.0, 0.0, source)), RangeTickDiagnostics(12_000), true)

    @Test fun exactSavedBarsReturnWithoutRescanningTheMillionQuoteTickWindow() = runBlocking {
        val dao = FakeDao()
        val store = RangeBarDiskStore(dao)
        val original = result(100, 200)
        store.save(gold, source, 1, 300, 1000, 0.01, true, original)
        val reopened = RangeBarDiskStore(dao)
        assertEquals(original, reopened.exact(gold, source, 1, 300, 1000, 0.01, true))
        assertNull(reopened.exact(gold, source, 1, 300, 100, 0.01, true))
        assertNull(reopened.exact(gold, source, 1, 300, 1000, 0.001, true))
        assertNull(reopened.exact(gold, "ctrader:demo:9:12", 1, 300, 1000, 0.01, true))
    }

    @Test fun warmPreviousSnapshotIsOnlyUsedWhenItPrecedesTheRequestedCutoff() = runBlocking {
        val dao = FakeDao()
        val store = RangeBarDiskStore(dao)
        val oldTo = 7_200_000L
        val oldFrom = 3_600_000L
        val original = result(oldFrom + 100, oldFrom + 200)
        store.save(gold, source, oldFrom, oldTo, 1000, 0.01, true, original)
        assertNotNull(store.newestCompatible(gold, source,
            oldFrom + 60_000L, oldTo + 60_000L, 1000, 0.01, true))
        assertNull(store.newestCompatible(gold, source,
            oldFrom - 60_000L, oldTo - 60_000L, 1000, 0.01, true))
    }

    @Test fun futureBarsNeverGetCommittedEvenIfCallerLabelsThemComplete() = runBlocking {
        val dao = FakeDao()
        val store = RangeBarDiskStore(dao)
        try {
            store.save(gold, source, 1, 300, 1000, 0.01, true, result(100, 999))
            fail("No future Replay candles may be saved under a past cutoff")
        } catch (_: IllegalArgumentException) { }
        assertTrue(dao.rows.isEmpty())
    }

    @Test fun zeroQuoteBrokerWindowsAreRetriedRatherThanPermanentlyCachedAsBlankCharts() = runBlocking {
        val dao = FakeDao()
        val store = RangeBarDiskStore(dao)
        store.save(gold, source, 1, 300, 1000, 0.01, true,
            VerifiedRangeBars(emptyList(), RangeTickDiagnostics(), false))
        assertTrue(dao.rows.isEmpty())
        assertNull(store.exact(gold, source, 1, 300, 1000, 0.01, true))
    }

    @Test fun rapidReplayStepsDoNotFillDiskWithThousandsOfNearlyIdenticalSnapshots() = runBlocking {
        val dao = FakeDao()
        val store = RangeBarDiskStore(dao)
        val start = 3_600_000L
        val finish = 7_200_000L
        store.save(gold, source, start, finish, 1000, 0.01, true,
            result(start + 100, start + 200))
        store.save(gold, source, start + 1_000, finish + 1_000, 1000, 0.01, true,
            result(start + 1_100, start + 1_200))
        assertEquals(1, dao.rows.size)
        store.save(gold, source, start + 360_000, finish + 360_000, 1000, 0.01, true,
            result(start + 360_100, start + 360_200))
        assertEquals(2, dao.rows.size)
    }
}
