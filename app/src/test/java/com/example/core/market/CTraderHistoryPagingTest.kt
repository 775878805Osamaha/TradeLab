package com.example.core.market

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CTraderHistoryPagingTest {
    @Test
    fun weeklyPagesStayContiguousAcrossGatewayDateLimit() = runBlocking {
        val week = 7L * 86_400_000L
        val first = 4L * 86_400_000L
        val expected = (0L..29L).map { first + it * week }

        val actual = CTraderHistoryPaging.load(first, expected.last(), week, timeOf = { it }) { start, end, count ->
            assertTrue(end + 1 - start <= 90L * 86_400_000L)
            val times = expected.filter { it in start..end }
            assertTrue(count >= times.size)
            CTraderHistoryPaging.Page(times, hasMore = false)
        }

        assertEquals(expected, actual)
    }

    @Test
    fun truncatedBrokerResponsePagesBackwardsWithoutDuplicatesOrInventingBars() = runBlocking {
        val interval = 180_000L
        val expected = listOf(0L, 2L * interval, 3L * interval, 4L * interval)
        var calls = 0
        val actual = CTraderHistoryPaging.load(0L, 4L * interval, interval, timeOf = { it }) { start, end, count ->
            calls++
            val available = expected.filter { it in start..end }
            CTraderHistoryPaging.Page(available.takeLast(2), hasMore = available.size > 2)
        }

        assertEquals(expected, actual)
        assertEquals(2, calls)
    }

    @Test
    fun aRealSingleCandleIsKeptEvenWhenBrokerClaimsHasMore() = runBlocking {
        val actual = CTraderHistoryPaging.load(300_000L, 300_000L, 300_000L, timeOf = { it }) { _, _, _ ->
            CTraderHistoryPaging.Page(listOf(300_000L), hasMore = true)
        }
        assertEquals(listOf(300_000L), actual)
    }

    @Test
    fun anEmptyTruncatedPageProbesFullCountAndDoesNotInventCandles() = runBlocking {
        val counts = mutableListOf<Int>()
        val result = CTraderHistoryPaging.load(0L, 900_000L, 300_000L, timeOf = { it }) { _, _, count ->
            counts.add(count)
            CTraderHistoryPaging.Page(emptyList<Long>(), hasMore = true)
        }
        assertEquals(emptyList<Long>(), result)
        assertEquals(listOf(5, 1000), counts)
    }

    @Test
    fun aFullCountProbeRecoversRealBarsFromAReportedEmptyPage() = runBlocking {
        val interval = 300_000L
        val actual = CTraderHistoryPaging.load(0L, 2L * interval, interval, timeOf = { it }) { _, _, count ->
            if (count < 1000) CTraderHistoryPaging.Page(emptyList<Long>(), hasMore = true)
            else CTraderHistoryPaging.Page(listOf(0L, interval, 2L * interval), hasMore = false)
        }
        assertEquals(listOf(0L, interval, 2L * interval), actual)
    }

    @Test
    fun aReturnedBarOutsideTheRequestedPageIsRejected(): Unit = runBlocking {
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                CTraderHistoryPaging.load(0L, 300_000L, 300_000L, timeOf = { it }) { _, _, _ ->
                    CTraderHistoryPaging.Page(listOf(600_000L), hasMore = false)
                }
            }
        }
    }
    @Test fun brokerShiftedDailyBarsAreNotLostBetweenDateWindows() = runBlocking {
        val day = 86_400_000L
        val hour = 3_600_000L
        val expected = listOf(89L * day + hour, 90L * day + hour)
        val actual = CTraderHistoryPaging.load(0L, 91L * day, day, timeOf = { it }) { from, to, _ ->
            CTraderHistoryPaging.Page(expected.filter { it in from..to }, false)
        }
        assertEquals(expected, actual)
    }

    @Test fun backwardCursorDoesNotSkipShiftedBarLessThanOneIntervalAway() = runBlocking {
        val h4 = 4L * 3_600_000L
        val expected = listOf(0L, h4, 2L * h4 - 600_000L)
        val actual = CTraderHistoryPaging.load(0L, 2L * h4, h4, timeOf = { it }) { from, to, _ ->
            val available = expected.filter { it in from..to }
            CTraderHistoryPaging.Page(available.takeLast(1), hasMore = available.size > 1)
        }
        assertEquals(expected, actual)
    }


}
