package com.example.core.market

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class RangeTickSuffixCacheTest {
    private val account = "ctrader:demo:111:222"
    private fun quote(time: Long, price: Double = 4050.0) = RangePriceTick(time, price)

    @Test fun contiguousNewestFirstSlicesRestoreExactChronologicalQuotes() {
        val cache = RangeTickSuffixCache()
        cache.remember("XAUUSD", account, 500, 1000,
            listOf(quote(500), quote(700), quote(1000)))
        cache.remember("XAUUSD", account, 200, 499,
            listOf(quote(200), quote(300), quote(499)))
        val recovered = cache.snapshot("XAUUSD", account, 1, 1000)!!
        assertEquals(200L, recovered.from)
        assertEquals(1000L, recovered.to)
        assertEquals(listOf(200L, 300L, 499L, 500L, 700L, 1000L),
            recovered.ticks.map { it.timestamp })
        assertEquals(listOf(500L, 700L, 1000L),
            cache.snapshot("XAUUSD", account, 500, 1000)!!.ticks.map { it.timestamp })
    }

    @Test fun emptyVerifiedPeriodStillCountsAsContiguousCoverage() {
        val cache = RangeTickSuffixCache()
        cache.remember("XAUUSD", account, 800, 1000, listOf(quote(900)))
        cache.remember("XAUUSD", account, 700, 799, emptyList())
        val result = cache.snapshot("XAUUSD", account, 700, 1000)!!
        assertEquals(700L, result.from)
        assertEquals(listOf(900L), result.ticks.map { it.timestamp })
    }

    @Test fun gapsOverlapAndOtherAccountsCannotMasqueradeAsCompleteHistory() {
        val cache = RangeTickSuffixCache()
        cache.remember("XAUUSD", account, 500, 1000, listOf(quote(600)))
        assertNull(cache.snapshot("XAUUSD", "ctrader:demo:other:222", 1, 1000))
        assertNull(cache.snapshot("EURUSD", account, 1, 1000))
        assertNull(cache.snapshot("XAUUSD", account, 1, 1001))
        cache.remember("XAUUSD", account, 300, 498, listOf(quote(400)))
        // The 499ms gap is not trusted; the old 500–1000ms page is discarded.
        assertNull(cache.snapshot("XAUUSD", account, 300, 1000))
        assertEquals(300L, cache.snapshot("XAUUSD", account, 300, 498)!!.from)
    }

    @Test fun memoryBoundDropsOldestPagesAndPreservesRecentContiguousSuffix() {
        val cache = RangeTickSuffixCache(maxTicks = 3)
        cache.remember("XAUUSD", account, 800, 1000, listOf(quote(800), quote(1000)))
        cache.remember("XAUUSD", account, 600, 799, listOf(quote(600), quote(799)))
        val suffix = cache.snapshot("XAUUSD", account, 1, 1000)!!
        assertEquals(800L, suffix.from)
        assertEquals(listOf(800L, 1000L), suffix.ticks.map { it.timestamp })
    }

    @Test fun abortedNewestFirstDownloadResumesWithoutRepeatingBrokerPages() = runBlocking {
        val cache = RangeTickSuffixCache()
        val hour = 3_600_000L
        val from = 1L
        val to = 6L * hour
        val known = listOf(from, hour, 5L * hour, to).mapIndexed { i, timestamp ->
            quote(timestamp, 4050.0 + i)
        }
        val initialCalls = mutableListOf<Pair<Long, Long>>()
        try {
            RangeTickBatchLoader.load(from, to,
                onVerifiedSlice = { start, end, prices ->
                    cache.remember("XAUUSD", account, start, end, prices)
                    throw CancellationException("cancelled after first completed slice")
                }) { start, end ->
                initialCalls.add(start to end)
                known.filter { it.timestamp in start..end }
            }
            fail("Expected cancellation")
        } catch (_: CancellationException) { }
        val retained = cache.snapshot("XAUUSD", account, from, to)!!
        assertEquals(listOf(to), retained.ticks.map { it.timestamp })
        val resumedCalls = mutableListOf<Pair<Long, Long>>()
        val older = RangeTickBatchLoader.load(from, retained.from - 1L) { start, end ->
            resumedCalls.add(start to end)
            known.filter { it.timestamp in start..end }
        }
        val combined = older + retained.ticks
        assertEquals(known, combined)
        assertEquals(RangeBarsEngine.build("XAUUSD", known, 0.01, 100, account),
            RangeBarsEngine.build("XAUUSD", combined, 0.01, 100, account))
        assertTrue(resumedCalls.all { it.second < retained.from })
        assertEquals(1, initialCalls.size)
    }
}
