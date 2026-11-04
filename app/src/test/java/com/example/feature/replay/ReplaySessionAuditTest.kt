package com.example.feature.replay

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReplaySessionAuditTest {
    private fun bar(time: Long, timeframe: Timeframe, source: String): Candle = Candle(
        symbol = if (source.startsWith("ctrader:")) "XAUUSD" else "BTCUSDT",
        timeframe = timeframe, openTime = time,
        open = 4000.0, high = 4002.0, low = 3999.0,
        close = 4001.0, volume = 10.0, source = source
    )

    @Test fun brokerDailyOpeningMinutesAreNotFalselyMarkedMisaligned() {
        val opening = 1_730_000_000_000L - Math.floorMod(1_730_000_000_000L, 60_000L) + 60_000L
        val candles = listOf(bar(opening, Timeframe.D1, "ctrader:demo:gold"),
            bar(opening + 86_400_000L + 120_000L, Timeframe.D1, "ctrader:demo:gold"))
        val audit = ReplaySessionAudit.inspect(candles, Timeframe.D1.minutes)
        assertEquals(0, audit.duplicateOrOutOfOrder)
        // The observed two-minute gap is reported, never fabricated away.
        assertEquals(1, audit.intervalGaps)
    }

    @Test fun binanceMondayWeeklyOpenIsAlignedAndOneHourShiftIsNot() {
        val week = Timeframe.W1.minutes.toLong() * 60_000L
        val monday = 4L * 86_400_000L + 2_900L * week
        val valid = ReplaySessionAudit.inspect(listOf(
            bar(monday, Timeframe.W1, "BINANCE_HISTORICAL"),
            bar(monday + week, Timeframe.W1, "BINANCE_HISTORICAL")
        ), Timeframe.W1.minutes)
        assertEquals(0, valid.duplicateOrOutOfOrder)
        assertTrue(valid.isClean)
        val shifted = ReplaySessionAudit.inspect(listOf(
            bar(monday + 3_600_000L, Timeframe.W1, "BINANCE_HISTORICAL")
        ), Timeframe.W1.minutes)
        assertEquals(1, shifted.duplicateOrOutOfOrder)
    }

    @Test fun brokerSubMinuteOrMixedSourceIsStillRejected() {
        val opening = 1_730_000_000_000L - Math.floorMod(1_730_000_000_000L, 60_000L)
        val candles = listOf(bar(opening, Timeframe.H4, "ctrader:demo:gold"),
            bar(opening + 14_400_001L, Timeframe.H4, "ctrader:demo:gold"))
        assertTrue(ReplaySessionAudit.inspect(candles, Timeframe.H4.minutes).duplicateOrOutOfOrder > 0)
        val mixed = listOf(bar(opening, Timeframe.H4, "ctrader:demo:gold"),
            bar(opening + 14_400_000L, Timeframe.H4, "ctrader:live:gold"))
        assertTrue(ReplaySessionAudit.inspect(mixed, Timeframe.H4.minutes).duplicateOrOutOfOrder > 0)
    }

    @Test fun emptySessionIsNotFalselyReportedAsCorrupt() {
        val result = ReplaySessionAudit.inspect(emptyList(), 15)
        assertTrue(result.isClean)
        assertEquals(0, result.candleCount)
        assertEquals(0L, result.missingBars)
    }

    @Test fun invalidIntervalIsRejected() {
        try {
            ReplaySessionAudit.inspect(emptyList(), 0)
            throw AssertionError("Expected invalid interval to fail")
        } catch (_: IllegalArgumentException) {
            // Verified.
        }
    }

    @Test fun auditExportIncludesAllIntegrityDimensions() {
        val result = ReplayDataAudit(20, 1000L, 2000L, 1, 2, 3, 4, 5, 6)
        val csv = ReplaySessionAudit.exportCsv(result, "BTCUSDT", "M15")
        assertTrue(csv.contains("invalid_ohlc_ranges,2"))
        assertTrue(csv.contains("interval_gaps,4"))
        assertTrue(csv.contains("estimated_missing_bars,5"))
        assertTrue(csv.contains("audit_clean,false"))
        assertTrue(csv.contains("symbol,\"BTCUSDT\""))
    }
}
