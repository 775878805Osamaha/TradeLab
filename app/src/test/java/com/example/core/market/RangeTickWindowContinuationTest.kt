package com.example.core.market

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class RangeTickWindowContinuationTest {
    private val source = "ctrader:demo:123:456"
    private val symbol = "XAUUSD"
    private val hour = 3_600_000L

    @Test fun interruptedOlderPanResumesExactBrokerHistoryWithoutRedownloadingSavedSlice() = runBlocking {
        val cache = RangeTickSuffixCache()
        val from = 1L
        val to = 4L * hour
        val fixture = listOf(from, hour, 2L * hour, 3L * hour, to).mapIndexed { index, t ->
            RangePriceTick(t, 4000.0 + index)
        }
        val initialCalls = mutableListOf<Pair<Long, Long>>()
        try {
            RangeTickWindowContinuation.downloadOlder(from, to, symbol, source, cache,
                onProgress = { _, _ -> throw CancellationException("left chart while loading") }
            ) { start, end ->
                initialCalls.add(start to end)
                fixture.filter { it.timestamp in start..end }
            }
            fail("Expected the first verified historical page to trigger cancellation")
        } catch (_: CancellationException) { }

        val firstComplete = cache.snapshot(symbol, source, from, to)!!
        assertEquals(to - hour + 1L, firstComplete.from)
        assertEquals(listOf(to), firstComplete.ticks.map { it.timestamp })
        assertEquals(1, initialCalls.size)

        val resumedCalls = mutableListOf<Pair<Long, Long>>()
        val counts = mutableListOf<Int>()
        val result = RangeTickWindowContinuation.downloadOlder(from, to, symbol, source, cache,
            onProgress = { count, _ -> counts.add(count) }) { start, end ->
            resumedCalls.add(start to end)
            fixture.filter { it.timestamp in start..end }
        }
        assertEquals(fixture, result)
        assertTrue(resumedCalls.isNotEmpty())
        assertTrue(resumedCalls.all { it.second < firstComplete.from })
        assertEquals(firstComplete.ticks.size, counts.first())
        assertEquals(fixture.size, counts.last())
    }

    @Test fun outdatedBrokerAccountNeverSuppliesVerifiedBackfill() = runBlocking {
        val cache = RangeTickSuffixCache()
        cache.remember(symbol, source, 2L * hour + 1L, 3L * hour,
            listOf(RangePriceTick(3L * hour, 4050.0)))
        val other = "ctrader:live:999:456"
        val requested = mutableListOf<Pair<Long, Long>>()
        val result = RangeTickWindowContinuation.downloadOlder(1L, 3L * hour,
            symbol, other, cache) { start, end ->
            requested.add(start to end)
            listOf(RangePriceTick(end, 4000.0 + requested.size))
        }
        assertEquals(2, result.size)
        assertEquals(1L, requested.first().first)
        assertEquals(3L * hour, requested.last().second)
        assertTrue(result.none { it.price == 4050.0 })
    }

    @Test fun cancelledDenseNestedBackfillResumesInsideOriginalHour() = runBlocking {
        val cache = RangeTickSuffixCache()
        val fixture = listOf(900L, 1_000L, 1_000L, 1_500L, 2_000L)
            .mapIndexed { index, t -> RangePriceTick(t, 4050.0 + index * 0.01) }
        var pages = 0
        try {
            RangeTickWindowContinuation.downloadOlder(900L, 2_000L, symbol, source, cache,
                onProgress = { _, _ -> if (++pages == 2) throw CancellationException("pan ended") }
            ) { start, end ->
                if (end - start > 200L) throw RangeTickHistoryTooDenseException("hasMore")
                fixture.filter { it.timestamp in start..end }
            }
            fail("Expected cancellation")
        } catch (_: CancellationException) { }

        val suffix = cache.snapshot(symbol, source, 900L, 2_000L)!!
        val resumed = mutableListOf<Pair<Long, Long>>()
        val recovered = RangeTickWindowContinuation.downloadOlder(900L, 2_000L,
            symbol, source, cache) { start, end ->
            resumed.add(start to end)
            if (end - start > 200L) throw RangeTickHistoryTooDenseException("hasMore")
            fixture.filter { it.timestamp in start..end }
        }
        assertEquals(fixture, recovered)
        assertTrue(resumed.all { it.second < suffix.from })
    }
}
