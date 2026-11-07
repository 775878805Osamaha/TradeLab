package com.example.data.local

import com.example.core.market.RangePriceTick
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class RangeTickDiskStoreTest {
    private class MemoryDao : RangeTickSliceDao {
        private val rows = linkedMapOf<List<Any>, RangeTickSliceEntity>()
        private fun key(source: String, symbol: String, from: Long, to: Long) =
            listOf(source, symbol, from, to)

        override suspend fun covered(source: String, symbol: String, from: Long, to: Long) =
            rows.values.filter { it.source == source && it.symbol == symbol &&
                it.toMillis >= from && it.fromMillis <= to }
                .map { RangeTickDiskSpan(it.fromMillis, it.toMillis) }

        override suspend fun find(source: String, symbol: String, from: Long, to: Long) =
            rows[key(source, symbol, from, to)]

        override suspend fun save(slice: RangeTickSliceEntity) {
            rows[key(slice.source, slice.symbol, slice.fromMillis, slice.toMillis)] = slice
        }

        override suspend fun discard(source: String, symbol: String, from: Long, to: Long) {
            rows.remove(key(source, symbol, from, to))
        }
    }

    @Test fun returningAfterARecreatedStoreReadsSavedRealQuotesWithoutNetwork() = runBlocking {
        val dao = MemoryDao()
        val quotes = listOf(RangePriceTick(10, 4071.37), RangePriceTick(20, 4072.37))
        var downloads = 0
        val first = RangeTickDiskStore(dao).getOrDownload("ctrader:account:1", "XAUUSD", 1, 30) { _, _ ->
            downloads++
            quotes
        }
        val second = RangeTickDiskStore(dao).getOrDownload("ctrader:account:1", "XAUUSD", 5, 25) { _, _ ->
            fail("Previously verified BID data must not download again")
            emptyList()
        }
        assertEquals(quotes, first)
        assertEquals(quotes, second)
        assertEquals(1, downloads)
    }

    @Test fun deepHistoricalBackfillOnlyFetchesUncoveredHoursAndKeepsOrder() = runBlocking {
        val dao = MemoryDao()
        val store = RangeTickDiskStore(dao)
        val recent = RangePriceTick(80, 4080.0)
        store.getOrDownload("ctrader:acc:1", "XAUUSD", 61, 100) { _, _ -> listOf(recent) }
        val received = mutableListOf<Pair<Long, Long>>()
        val combined = store.getOrDownload("ctrader:acc:1", "XAUUSD", 1, 100) { from, to ->
            received += from to to
            listOf(RangePriceTick(20, 4060.0))
        }
        assertEquals(listOf(1L to 60L), received)
        assertEquals(listOf(RangePriceTick(20, 4060.0), recent), combined)
        // Another app launch reuses both exact intervals with no network.
        assertEquals(combined, RangeTickDiskStore(dao).getOrDownload(
            "ctrader:acc:1", "XAUUSD", 1, 100) { _, _ ->
                fail("The completed historical range is persisted")
                emptyList()
            })
    }

    @Test fun anEmptyWeekendPageIsPersistedAndDifferentAccountsDoNotShareIt() = runBlocking {
        val dao = MemoryDao()
        val cache = RangeTickDiskStore(dao)
        cache.getOrDownload("ctrader:acc:1", "XAUUSD", 1, 100) { _, _ -> emptyList() }
        cache.getOrDownload("ctrader:acc:1", "XAUUSD", 1, 100) { _, _ ->
            fail("Empty verified market sessions must be cached")
            emptyList()
        }
        var otherAccountCalled = false
        cache.getOrDownload("ctrader:acc:2", "XAUUSD", 1, 100) { _, _ ->
            otherAccountCalled = true
            emptyList()
        }
        assertTrue(otherAccountCalled)
    }

    @Test fun corruptedSavedPageFallsBackToRealBrokerAndInvalidDataIsNotSaved() = runBlocking {
        val dao = MemoryDao()
        dao.save(RangeTickSliceEntity("ctrader:acc:1", "XAUUSD", 1, 20, 1,
            byteArrayOf(1, 2, 3), 0L))
        val cache = RangeTickDiskStore(dao)
        assertEquals(listOf(RangePriceTick(5, 100.0)), cache.getOrDownload(
            "ctrader:acc:1", "XAUUSD", 1, 20) { _, _ -> listOf(RangePriceTick(5, 100.0)) })
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                cache.getOrDownload("ctrader:acc:1", "XAUUSD", 21, 40) { _, _ ->
                    listOf(RangePriceTick(41, 999.0))
                }
            }
        }
        assertTrue(dao.covered("ctrader:acc:1", "XAUUSD", 21, 40).isEmpty())
    }

    @Test fun cancelledBrokerRequestCannotMarkTheGapAsSaved() = runBlocking {
        val dao = MemoryDao()
        val store = RangeTickDiskStore(dao)
        try {
            store.getOrDownload("ctrader:acc:1", "XAUUSD", 1, 20) { _, _ ->
                throw CancellationException("Chart context changed")
            }
            fail("Cancellation must propagate")
        } catch (_: CancellationException) { }
        assertTrue(dao.covered("ctrader:acc:1", "XAUUSD", 1, 20).isEmpty())
    }
}
