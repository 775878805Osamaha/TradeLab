package com.example.core.market

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CTraderHistoryPagingTest {
    @Test
    fun weeklyPagesStayContiguousAcrossGatewayDateLimit() = runBlocking {
        val week = 7L * 86_400_000L
        val first = 4L * 86_400_000L
        val expected = (0L..29L).map { first + it * week }

        val actual = CTraderHistoryPaging.load(first, expected.last(), week) { start, end, count ->
            assertTrue(end + 1 - start <= 90L * 86_400_000L)
            val times = (start..end step week).toList()
            assertEquals(times.size, count)
            CTraderHistoryPaging.Page(times, hasMore = false)
        }

        assertEquals(expected, actual)
    }

    @Test
    fun truncatedBrokerResponseIsSplitWithoutDuplicatesOrInventingBars() = runBlocking {
        val interval = 180_000L
        val expected = listOf(0L, 2L * interval, 3L * interval, 4L * interval)
        val actual = CTraderHistoryPaging.load(0L, 4L * interval, interval) { start, end, count ->
            if (count > 2) CTraderHistoryPaging.Page(emptyList(), hasMore = true)
            else CTraderHistoryPaging.Page(expected.filter { it in start..end }, hasMore = false)
        }

        assertEquals(expected, actual)
    }
}
