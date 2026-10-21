package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class HistoricalCandleIntegrityTest {
    private fun candle(at: Long, close: Double = 101.0, source: String = "PROVIDER") =
        Candle(symbol = "XAUUSD", timeframe = Timeframe.M1, openTime = at,
            open = 100.0, high = 102.0, low = 99.0, close = close, source = source)

    @Test fun sortsAuthenticCandles() {
        val result = HistoricalCandleIntegrity.validate(
            listOf(candle(120_000), candle(60_000)), 0, 180_000, "PROVIDER")
        assertEquals(listOf(60_000L, 120_000L), result.map { it.openTime })
    }

    @Test fun rejectsDuplicates() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(listOf(candle(60_000), candle(60_000)), 0, 180_000)
        }
    }

    @Test fun rejectsBadOhlc() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(listOf(candle(60_000, 105.0)), 0, 180_000)
        }
    }

    @Test fun rejectsWrongSource() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(listOf(candle(60_000)), 0, 180_000, "VERIFIED")
        }
    }

    @Test fun rejectsWrongInstrument() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(listOf(candle(60_000)), 0, 180_000,
                expectedSymbol = "EURUSD")
        }
    }

    @Test fun rejectsWrongTimeframe() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(listOf(candle(60_000)), 0, 180_000,
                expectedTimeframe = Timeframe.M5)
        }
    }

    @Test fun rejectsIncompleteRange() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(listOf(candle(120_000)), 0, 150_000)
        }
    }
}
