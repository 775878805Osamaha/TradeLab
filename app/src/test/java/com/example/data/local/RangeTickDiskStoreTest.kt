package com.example.data.local

import com.example.core.market.RangePriceTick
import com.example.core.market.RangeTickCacheCodec
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.*
import org.junit.Test

class RangeTickDiskStoreTest {
    private class MemoryDao : RangeTickSliceDao {
        private val rows = linkedMapOf<List<Any>, RangeTickSliceEntity>()
        var diskReads = 0
        private fun key(source: String, symbol: String, from: Long, to: Long) =
            listOf(source, symbol, from, to)

        override suspend fun covered(source: String, symbol: String, from: Long, to: Long) =
            rows.values.filter { it.source == source && it.symbol == symbol &&
                it.toMillis >= from && it.fromMillis <= to }
                .map { RangeTickDiskSpan(it.fromMillis, it.toMillis,
                    it.quoteCount, it.savedAtMillis) }

        override suspend fun find(source: String, symbol: String, from: Long, to: Long): RangeTickSliceEntity? {
            diskReads++
            return rows[key(source, symbol, from, to)]
        }

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

    @Test fun repeatedDiskCachedRangePansDecodeEachQuotePageOnlyOncePerAppProcess() = runBlocking {
        val dao = MemoryDao()
        val quotes = listOf(RangePriceTick(10L, 4071.37), RangePriceTick(20L, 4072.37))
        dao.save(RangeTickSliceEntity("ctrader:account:1", "XAUUSD", 1L, 30L,
            quotes.size, RangeTickCacheCodec.encode(quotes, 1L, 30L), System.currentTimeMillis()))
        val store = RangeTickDiskStore(dao)
        assertEquals(quotes, store.getOrDownload("ctrader:account:1", "XAUUSD", 1L, 30L) { _, _ ->
            fail("Verified disk data must not be redownloaded")
            emptyList()
        })
        assertEquals(1, dao.diskReads)
        assertEquals(listOf(quotes.last()), store.getOrDownload(
            "ctrader:account:1", "XAUUSD", 15L, 30L) { _, _ ->
            fail("Moving over the same disk page must not redownload")
            emptyList()
        })
        assertEquals(1, dao.diskReads)
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

    @Test fun anExpiredEmptyPageIsRedownloadedButNearbyFreshEmptyPagesAreReused() = runBlocking {
        val now = 10L * 3_600_000L
        var clock = now
        val dao = MemoryDao()
        val store = RangeTickDiskStore(dao, nowMillis = { clock })
        val source = "ctrader:acc:1"
        var downloads = 0
        store.getOrDownload(source, "XAUUSD", now - 100L, now) { _, _ ->
            downloads++
            emptyList()
        }
        clock += 14L * 60_000L
        store.getOrDownload(source, "XAUUSD", now - 100L, now) { _, _ ->
            fail("Fresh empty results are temporarily cached")
            emptyList()
        }
        assertFalse(store.hasExpiredEmptyPages(source, "XAUUSD", now - 100L, now))
        clock += 2L * 60_000L
        assertTrue(store.hasExpiredEmptyPages(source, "XAUUSD", now - 100L, now))
        val recovered = listOf(RangePriceTick(now - 50L, 4071.37))
        assertEquals(recovered, store.getOrDownload(source, "XAUUSD", now - 100L, now) { _, _ ->
            downloads++
            recovered
        })
        assertEquals(2, downloads)
        clock += 365L * 24L * 3_600_000L
        assertFalse(store.hasExpiredEmptyPages(source, "XAUUSD", now - 100L, now))
        assertEquals(recovered, store.getOrDownload(source, "XAUUSD", now - 100L, now) { _, _ ->
            fail("Real BID quotes must never be discarded by empty-page expiration")
            emptyList()
        })
    }

    @Test fun oldEmptyHistoryPagesAreRevalidatedAfterADayWithoutDiscardingRecentRealQuotes() = runBlocking {
        val historicTo = 2L * 3_600_000L
        val currentTime = historicTo + 10L * 24L * 3_600_000L
        var clock = currentTime
        val dao = MemoryDao()
        val store = RangeTickDiskStore(dao, nowMillis = { clock })
        val source = "ctrader:acc:1"
        store.getOrDownload(source, "XAUUSD", 1L, historicTo) { _, _ -> emptyList() }
        clock += 23L * 3_600_000L
        assertFalse(store.hasExpiredEmptyPages(source, "XAUUSD", 1L, historicTo))
        clock += 2L * 3_600_000L
        assertTrue(store.hasExpiredEmptyPages(source, "XAUUSD", 1L, historicTo))
        val refreshed = listOf(RangePriceTick(50L, 4071.25))
        assertEquals(refreshed, store.getOrDownload(source, "XAUUSD", 1L, historicTo) { _, _ -> refreshed })
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

    @Test fun concurrentSameBrokerRequestsDownloadMissingBidPageOnlyOnce() = runBlocking {
        val dao = MemoryDao()
        val store = RangeTickDiskStore(dao)
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        var downloads = 0
        val verified = listOf(RangePriceTick(10L, 4071.37))
        val first = async {
            store.getOrDownload("ctrader:acc:1", "XAUUSD", 1L, 20L) { _, _ ->
                downloads++
                entered.complete(Unit)
                release.await()
                verified
            }
        }
        entered.await()
        val waiting = async {
            store.getOrDownload("ctrader:acc:1", "XAUUSD", 1L, 20L) { _, _ ->
                fail("A second overlapping request must reuse the first verified disk page")
                emptyList()
            }
        }
        yield()
        assertFalse(waiting.isCompleted)
        release.complete(Unit)
        assertEquals(verified, first.await())
        assertEquals(verified, waiting.await())
        assertEquals(1, downloads)
    }

    @Test fun aSlowAccountDownloadNeverBlocksAnotherBrokerAccount() = runBlocking {
        val dao = MemoryDao()
        val store = RangeTickDiskStore(dao)
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val first = async {
            store.getOrDownload("ctrader:acc:1", "XAUUSD", 1L, 20L) { _, _ ->
                entered.complete(Unit)
                release.await()
                listOf(RangePriceTick(10L, 4071.37))
            }
        }
        entered.await()
        try {
            val other = withTimeout(1_000L) {
                store.getOrDownload("ctrader:acc:2", "XAUUSD", 1L, 20L) { _, _ ->
                    listOf(RangePriceTick(15L, 4080.0))
                }
            }
            assertEquals(listOf(RangePriceTick(15L, 4080.0)), other)
        } finally {
            release.complete(Unit)
            first.await()
        }
    }

    @Test fun cancellingAWaitingPanDoesNotCancelItsVerifiedBrokerPredecessor() = runBlocking {
        val dao = MemoryDao()
        val store = RangeTickDiskStore(dao)
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val first = async {
            store.getOrDownload("ctrader:acc:1", "XAUUSD", 1L, 20L) { _, _ ->
                entered.complete(Unit)
                release.await()
                listOf(RangePriceTick(10L, 4071.37))
            }
        }
        entered.await()
        val obsoletePan = async {
            store.getOrDownload("ctrader:acc:1", "XAUUSD", 1L, 20L) { _, _ ->
                fail("Cancelled pan must not issue a second network request")
                emptyList()
            }
        }
        yield()
        obsoletePan.cancel()
        try { obsoletePan.await(); fail("Cancelled pan should not complete") }
        catch (_: CancellationException) { }
        release.complete(Unit)
        assertEquals(listOf(RangePriceTick(10L, 4071.37)), first.await())
        assertEquals(listOf(RangePriceTick(10L, 4071.37)), store.getOrDownload(
            "ctrader:acc:1", "XAUUSD", 1L, 20L) { _, _ ->
            fail("Verified BID page must survive cancellation of the waiting pan")
            emptyList()
        })
    }
}
