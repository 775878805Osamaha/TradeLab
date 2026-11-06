package com.example.core.market

import com.example.core.model.Timeframe
import com.example.core.model.Candle
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

    @Test fun dailyDstSessionShiftUsesObservedNextOpenWithoutFakeCandles() {
        val day = 86_400_000L
        val before = com.example.core.model.Candle("XAUUSD", Timeframe.D1,
            22L * 3_600_000L, 22L * 3_600_000L + day,
            4000.0, 4002.0, 3999.0, 4001.0, 12.0, "ctrader:demo:a:42")
        val after = before.copy(openTime = before.openTime + day - 3_600_000L,
            closeTime = before.openTime + 2L * day - 3_600_000L)
        val corrected = CTraderTrendbars.closeAtNextBrokerOpen(listOf(after, before))
        assertEquals(after.openTime, corrected.first().closeTime)
        assertEquals(2, corrected.size)
        assertTrue(DataIntegrityValidator.validateHistoricalSeries(corrected).isValid)
    }

    @Test fun h2UsesTwoActualHourlyBarsEvenWhenTheirOpenTicksShiftByAMinute() {
        val hour = 3_600_000L
        val source = "ctrader:demo:test:42"
        val first = Candle("XAUUSD", Timeframe.H1, 24L * hour + 60_000L,
            25L * hour + 60_000L, 4000.0, 4010.0, 3990.0, 4005.0, 10.0, source)
        val second = first.copy(openTime = 25L * hour, closeTime = 26L * hour,
            open = 4005.0, high = 4012.0, low = 4001.0, close = 4008.0, volume = 12.0)
        val paired = CTraderTrendbars.aggregateVerifiedH2(listOf(second, first))
        assertEquals(1, paired.size)
        val result = paired.single()
        assertEquals(Timeframe.H2, result.timeframe)
        assertEquals(first.openTime, result.openTime)
        assertEquals(second.closeTime, result.closeTime)
        assertEquals(4012.0, result.high, 0.0)
        assertEquals(3990.0, result.low, 0.0)
        assertEquals(22.0, result.volume, 0.0)
        assertTrue(DataIntegrityValidator.validateHistoricalSeries(paired).isValid)
    }

    @Test fun missingHourlyBarNeverCreatesAnH2Candle() {
        val hour = 3_600_000L
        val source = "ctrader:demo:test:42"
        val first = Candle("XAUUSD", Timeframe.H1, 24L * hour,
            25L * hour, 4000.0, 4001.0, 3999.0, 4000.5, 10.0, source)
        val later = first.copy(openTime = 26L * hour, closeTime = 27L * hour)
        assertTrue(CTraderTrendbars.aggregateVerifiedH2(listOf(first, later)).isEmpty())
    }
}
