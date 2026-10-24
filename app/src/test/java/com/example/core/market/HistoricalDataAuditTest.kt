package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class HistoricalDataAuditTest {
    private fun bar(time: Long, symbol: String = "XAUUSD") = Candle(
        symbol = symbol, timeframe = Timeframe.M1,
        openTime = time, open = 4000.0, high = 4005.0,
        low = 3995.0, close = 4001.0, source = "HISTORICAL"
    )
    private val now = 10_000_000L

    @Test fun emptySeriesIsUnsafe() {
        val result = HistoricalDataAudit.inspect(emptyList(), now)
        assertFalse(result.safeForBacktest)
        assertEquals(0, result.total)
    }

    @Test fun validOrderedHistoryIsSafe() {
        val result = HistoricalDataAudit.inspect(listOf(bar(60_000), bar(120_000)), now)
        assertTrue(result.safeForBacktest)
        assertEquals(2, result.valid)
        assertEquals(0L, result.missingIntervals)
    }

    @Test fun duplicateBarIsDetected() {
        val result = HistoricalDataAudit.inspect(listOf(bar(60_000), bar(60_000)), now)
        assertEquals(1, result.duplicates)
        assertFalse(result.safeForBacktest)
    }

    @Test fun reverseTimeIsDetected() {
        val result = HistoricalDataAudit.inspect(listOf(bar(120_000), bar(60_000)), now)
        assertEquals(1, result.outOfOrder)
        assertFalse(result.safeForBacktest)
    }

    @Test fun missingIntervalsAreCountedWithoutFabrication() {
        val result = HistoricalDataAudit.inspect(listOf(bar(60_000), bar(240_000)), now)
        assertEquals(2L, result.missingIntervals)
        assertEquals(2L, result.largestGapIntervals)
        assertEquals(2, result.total)
    }

    @Test fun mixedSymbolsAreRejected() {
        val result = HistoricalDataAudit.inspect(listOf(bar(60_000), bar(120_000, "EURUSD")), now)
        assertEquals(1, result.mixedInstruments)
        assertFalse(result.safeForBacktest)
    }

    @Test fun futureCandlesAreUnsafe() {
        val result = HistoricalDataAudit.inspect(listOf(bar(60_000), bar(9_960_000)), now)
        assertEquals(1, result.futureBars)
        assertFalse(result.safeForBacktest)
    }

    @Test fun reportDoesNotModifyInput() {
        val bars = listOf(bar(180_000), bar(60_000))
        HistoricalDataAudit.inspect(bars, now)
        assertEquals(180_000L, bars.first().openTime)
    }
}
