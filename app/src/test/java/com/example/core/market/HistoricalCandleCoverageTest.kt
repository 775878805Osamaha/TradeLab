package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoricalCandleCoverageTest {
    private fun bar(t: Long) = Candle(
        symbol = "BTCUSDT", timeframe = Timeframe.M1,
        openTime = t, open = 100.0, high = 102.0, low = 99.0, close = 101.0,
        source = "BINANCE_HISTORICAL"
    )

    @Test fun completeWindow() {
        assertTrue(HistoricalCandleCoverage.isComplete(
            listOf(bar(60_000), bar(120_000), bar(180_000)), 60_000, 180_000, 60_000))
    }

    @Test fun missingMiddleCandle() {
        assertFalse(HistoricalCandleCoverage.isComplete(
            listOf(bar(60_000), bar(180_000)), 60_000, 180_000, 60_000))
    }

    @Test fun duplicateCandle() {
        assertFalse(HistoricalCandleCoverage.isComplete(
            listOf(bar(60_000), bar(60_000), bar(180_000)), 60_000, 180_000, 60_000))
    }

    @Test fun unalignedRequestStart() {
        assertTrue(HistoricalCandleCoverage.isComplete(
            listOf(bar(120_000), bar(180_000)), 90_000, 180_000, 60_000))
    }

    @Test fun weeklyCacheMustBeRefetched() {
        assertFalse(HistoricalCandleCoverage.isComplete(
            listOf(bar(60_000)), 0, 604_800_000, 604_800_000))
    }
}
