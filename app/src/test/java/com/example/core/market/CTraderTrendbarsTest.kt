package com.example.core.market

import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class CTraderTrendbarsTest {
    private fun bar(minute: Long = 1) = CTraderTrendbars.Bar(
        minute, 400_000_000, 125_000, 250_000, 200_000, 17)
    private fun decode(bars: List<CTraderTrendbars.Bar>, now: Long = 300_000) =
        CTraderTrendbars.decode(bars, "XAUUSD", Timeframe.M1, 2,
            "demo/account-a/42", 0, 300_000, now)

    @Test fun fixedPriceScaleAndMinuteTimestamp() {
        val candle = decode(listOf(bar())).single()
        assertEquals(4001.25, candle.open, 0.0)
        assertEquals(4002.50, candle.high, 0.0)
        assertEquals(4000.0, candle.low, 0.0)
        assertEquals(4002.0, candle.close, 0.0)
        assertEquals(60_000L, candle.openTime)
        assertEquals(17.0, candle.volume, 0.0)
        assertEquals("ctrader:demo/account-a/42", candle.source)
    }

    @Test fun liveBarCannotEnterReplay() {
        assertEquals(listOf(60_000L), decode(listOf(bar(1), bar(2)), 150_000).map { it.openTime })
    }

    @Test fun sortsWithoutFillingMarketGaps() {
        assertEquals(listOf(60_000L, 180_000L), decode(listOf(bar(3), bar(1))).map { it.openTime })
    }

    @Test fun rejectsConflictingTimestamps() {
        assertThrows(IllegalArgumentException::class.java) { decode(listOf(bar(), bar().copy(deltaClose = 0))) }
    }

    @Test fun rejectsInvalidRawOhlcBeforeRounding() {
        assertThrows(IllegalArgumentException::class.java) { decode(listOf(bar().copy(deltaOpen = 250_001))) }
    }

    @Test fun rejectsNegativeTickVolume() {
        assertThrows(IllegalArgumentException::class.java) { decode(listOf(bar().copy(volume = -1))) }
    }

    @Test fun detectsPriceOverflow() {
        assertThrows(ArithmeticException::class.java) { decode(listOf(bar().copy(low = Long.MAX_VALUE))) }
    }

    @Test fun periodCodesAreNotMinutesOrEnumOrdinals() {
        assertEquals(7, CTraderTrendbars.period(Timeframe.M15))
        assertEquals(9, CTraderTrendbars.period(Timeframe.H1))
        assertEquals(13, CTraderTrendbars.period(Timeframe.W1))
        assertNull(CTraderTrendbars.period(Timeframe.H2))
        assertThrows(IllegalArgumentException::class.java) {
            CTraderTrendbars.decode(emptyList(), "XAUUSD", Timeframe.H2, 2, "demo/a/42", 0, 300_000, 300_000)
        }
    }
}
