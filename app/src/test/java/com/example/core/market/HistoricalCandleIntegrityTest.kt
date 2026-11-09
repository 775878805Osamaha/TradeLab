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

    @Test fun acceptsMondayAlignedWeeklyCandle() {
        val monday = 345_600_000L
        val weekly = candle(monday).copy(timeframe = Timeframe.fromCode("W1"))
        val result = HistoricalCandleIntegrity.validate(
            listOf(weekly), monday, monday + 604_800_000L,
            expectedTimeframe = Timeframe.fromCode("W1")
        )
        assertEquals(1, result.size)
    }

    @Test fun rejectsThursdayAlignedWeeklyCandle() {
        val weekly = candle(604_800_000L).copy(timeframe = Timeframe.fromCode("W1"))
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(
                listOf(weekly), 0, 1_209_600_000L,
                expectedTimeframe = Timeframe.fromCode("W1")
            )
        }
    }

    @Test fun acceptsAuthenticOffGridBrokerBarOpensForH4D1AndW1() {
        val hour = 3_600_000L
        val cases = listOf(
            Timeframe.H4 to hour,
            Timeframe.D1 to 22L * hour,
            Timeframe.W1 to (3L * 24 + 22) * hour
        )
        for ((tf, open) in cases) {
            val bar = candle(open, source = "ctrader:demo:account:42")
                .copy(timeframe = tf, closeTime = open + tf.minutes * 60_000L)
            val result = HistoricalCandleIntegrity.validate(
                listOf(bar), 0L, bar.closeTime + 1L,
                expectedSource = bar.source, expectedTimeframe = tf)
            assertEquals(listOf(open), result.map { it.openTime })
        }
    }

    @Test fun keepsFixedGridValidationForBinanceAndRejectsSubminuteBrokerBars() {
        val hour = 3_600_000L
        val offGridBinance = candle(hour, source = "BINANCE_HISTORICAL")
            .copy(timeframe = Timeframe.H4, closeTime = hour + 4L * hour)
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(listOf(offGridBinance), 0, offGridBinance.closeTime + 1)
        }
        val nonMinuteBroker = candle(hour + 1000L, source = "ctrader:demo:account:42")
            .copy(timeframe = Timeframe.H4, closeTime = 5L * hour + 1000L)
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(listOf(nonMinuteBroker), 0, nonMinuteBroker.closeTime + 1)
        }
    }

    @Test fun rejectsIncompleteRange() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(listOf(candle(120_000)), 0, 150_000)
        }
    }
    @Test fun rejectsBarClosingBeforeOpening() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(
                listOf(candle(60_000).copy(closeTime = 59_999)), 0, 180_000
            )
        }
    }

    @Test fun rejectsBarExtendingBeyondTimeframe() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(
                listOf(candle(60_000).copy(closeTime = 150_000)), 0, 180_000
            )
        }
    }

    @Test fun rejectsMissingHistoricalSource() {
        assertThrows(IllegalArgumentException::class.java) {
            HistoricalCandleIntegrity.validate(
                listOf(candle(60_000).copy(source = "")), 0, 180_000
            )
        }
    }

}
