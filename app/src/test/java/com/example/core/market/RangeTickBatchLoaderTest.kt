package com.example.core.market

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class RangeTickBatchLoaderTest {
    @Test fun denseBrokerRequestsAreSplitIntoContiguousRealTickSlices() = runBlocking {
        val minute = 60_000L
        val from = 1L
        val to = from + 6L * 60L * minute
        val realTicks = (0..12).map { i ->
            RangePriceTick(from + i * 30L * minute, 2000.0 + i)
        }
        val requests = mutableListOf<Pair<Long, Long>>()
        val loaded = RangeTickBatchLoader.load(from, to) { start, end ->
            requests.add(start to end)
            if (end - start > 90L * minute)
                throw RangeTickHistoryTooDenseException("dense cTrader tick history")
            realTicks.filter { it.timestamp in start..end }
        }
        assertEquals(realTicks, loaded)
        assertTrue(requests.size > 2)
        assertTrue(requests.any { it.second - it.first <= 90L * minute })
    }

    @Test fun consecutiveBrokerSlicesDoNotRepeatBoundaryTicks() = runBlocking {
        val hour = 3_600_000L
        val from = 1L
        val to = 12L * hour
        val expected = listOf(from, 6L * hour, 6L * hour + 1L, to)
        val result = RangeTickBatchLoader.load(from, to) { start, end ->
            expected.filter { it in start..end }.map { RangePriceTick(it, 2070.0) }
        }
        assertEquals(expected, result.map { it.timestamp })
    }

    @Test fun unavailableBrokerDataIsNotSwallowedOrFabricated() = runBlocking {
        try {
            RangeTickBatchLoader.load(1L, 7L) { _, _ ->
                throw IOException("broker unavailable")
            }
            fail("Unavailable broker quotes must fail")
        } catch (expected: IOException) {
            assertEquals("broker unavailable", expected.message)
        }
    }

    @Test fun rejectsInvalidTickPageInsteadOfDisplayingMisorderedBars() = runBlocking {
        try {
            RangeTickBatchLoader.load(1L, 9L) { _, _ ->
                listOf(RangePriceTick(8L, 2000.0), RangePriceTick(7L, 2000.1))
            }
            fail("Unordered quotes must fail")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message.orEmpty().contains("Invalid ordered"))
        }
    }
}
