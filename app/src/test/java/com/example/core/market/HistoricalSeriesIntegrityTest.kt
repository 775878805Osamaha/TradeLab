package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoricalSeriesIntegrityTest {
    private fun candle(
        openTime: Long,
        symbol: String = "XAUUSD",
        high: Double = 2050.0,
        low: Double = 2000.0,
        timeframe: Timeframe = Timeframe.M15
    ) = Candle(
        symbol = symbol,
        timeframe = timeframe,
        openTime = openTime,
        closeTime = openTime + 900_000L,
        open = 2020.0,
        high = high,
        low = low,
        close = 2030.0,
        volume = 0.0,
        source = "HISTORICAL"
    )

    @Test fun validHistoricalBarsAreAccepted() {
        assertTrue(DataIntegrityValidator.validateHistoricalSeries(
            listOf(candle(900_000L), candle(1_800_000L), candle(3_600_000L))
        ).isValid)
    }

    @Test fun duplicateTimestampsAreRejected() {
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(
            listOf(candle(900_000L), candle(900_000L))
        ).isValid)
    }

    @Test fun unsortedTimestampsAreRejected() {
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(
            listOf(candle(1_800_000L), candle(900_000L))
        ).isValid)
    }

    @Test fun mixedSymbolsAndTimeframesAreRejected() {
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(
            listOf(candle(900_000L), candle(1_800_000L, symbol = "EURUSD"))
        ).isValid)
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(
            listOf(candle(900_000L), candle(1_800_000L, timeframe = Timeframe.H1))
        ).isValid)
    }

    @Test fun invalidOhlcIsRejectedInsteadOfSilentlyDropped() {
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(
            listOf(candle(900_000L), candle(1_800_000L, high = 2010.0))
        ).isValid)
    }

    @Test fun emptyHistoryIsRejected() {
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(emptyList()).isValid)
    }
}
