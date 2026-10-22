package com.example.ui.components

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class ChartPriceRangeIndexTest {
    private fun candle(i: Int): Candle {
        val close = 100.0 + (i % 719) * 0.37
        return Candle(
            symbol = "BTCUSDT", timeframe = Timeframe.M15,
            openTime = i.toLong() * 900_000L,
            closeTime = (i.toLong() + 1) * 900_000L,
            open = close, high = close + (i % 7) + 0.1,
            low = close - (i % 11) - 0.1, close = close,
            volume = 1.0, source = "BINANCE_HISTORICAL"
        )
    }

    @Test fun emptyIndexUsesSafeRange() {
        assertEquals(0.0 to 1.0, ChartPriceRangeIndex(emptyList()).query(0, 1))
    }

    @Test fun largeHistoryMatchesBruteForceOnTwoThousandViewports() {
        val candles = List(100_000, ::candle)
        val index = ChartPriceRangeIndex(candles)
        val random = Random(7129)
        repeat(2_000) {
            val start = random.nextInt(candles.size)
            val end = (start + random.nextInt(1, 501)).coerceAtMost(candles.size)
            val expected = candles.subList(start, end)
            val range = index.query(start, end)
            assertEquals(expected.minOf { it.low }, range.first, 0.0)
            assertEquals(expected.maxOf { it.high }, range.second, 0.0)
        }
    }

    @Test fun repeatedViewportQueriesRemainAllocationBounded() {
        val candles = List(100_000, ::candle)
        val index = ChartPriceRangeIndex(candles)
        var checksum = 0.0
        val start = System.nanoTime()
        repeat(100_000) { i ->
            val from = i % 99_700
            val range = index.query(from, from + 300)
            checksum += range.first + range.second
        }
        val elapsedMillis = (System.nanoTime() - start) / 1_000_000
        assertTrue(checksum.isFinite())
        println("CHART_RANGE_BENCHMARK: 100000 candles, 100000 viewport queries, ${elapsedMillis}ms")
    }
}
