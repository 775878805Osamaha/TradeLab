package com.example.core.replay

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class HistoricalReplayIntegrityTest {
    private fun candle(time: Long) = Candle(
        symbol = "XAUUSD",
        timeframe = Timeframe.M15,
        openTime = time,
        closeTime = time + 900_000L,
        open = 2010.0,
        high = 2020.0,
        low = 2000.0,
        close = 2015.0,
        volume = 0.0,
        source = "HISTORICAL"
    )

    @Test fun enginePreservesValidHistoricalBarCountAndOrdering() {
        val engine = HistoricalReplayEngine()
        val candles = listOf(candle(900_000L), candle(1_800_000L), candle(3_600_000L))
        engine.initialize(candles, startIndex = 0)
        assertEquals(3, engine.totalCandles.value)
        assertEquals(900_000L, engine.currentCandle.value?.openTime)
        engine.pause()
    }

    @Test fun engineRejectsDuplicatesRatherThanSilentlyDroppingTrades() {
        val engine = HistoricalReplayEngine()
        assertThrows(IllegalArgumentException::class.java) {
            engine.initialize(listOf(candle(900_000L), candle(900_000L)))
        }
    }

    @Test fun engineRejectsOutOfOrderHistoryRatherThanSortingIt() {
        val engine = HistoricalReplayEngine()
        assertThrows(IllegalArgumentException::class.java) {
            engine.initialize(listOf(candle(1_800_000L), candle(900_000L)))
        }
    }
}
