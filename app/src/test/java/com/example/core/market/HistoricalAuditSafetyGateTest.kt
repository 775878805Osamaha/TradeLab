package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class HistoricalAuditSafetyGateTest {
    private fun bar(t: Long) = Candle(
        symbol = "EURUSD", timeframe = Timeframe.M1,
        openTime = t, open = 1.10, high = 1.11, low = 1.09, close = 1.105,
        source = "HISTORICAL"
    )

    @Test fun completeClosedHistoryPasses() {
        assertTrue(HistoricalDataAudit.inspect(
            listOf(bar(60_000), bar(120_000)), 300_000L).safeForBacktest)
    }

    @Test fun currentUnclosedCandleFails() {
        assertFalse(HistoricalDataAudit.inspect(
            listOf(bar(60_000), bar(120_000)), 150_000L).safeForBacktest)
    }

    @Test fun repeatedTimestampFails() {
        assertFalse(HistoricalDataAudit.inspect(
            listOf(bar(60_000), bar(60_000)), 300_000L).safeForBacktest)
    }

    @Test fun marketClosureGapIsNotFabricatedOrRejected() {
        val audit = HistoricalDataAudit.inspect(
            listOf(bar(60_000), bar(420_000)), 600_000L)
        assertTrue(audit.safeForBacktest)
        assertEquals(5L, audit.missingIntervals)
        assertEquals(2, audit.total)
    }

    @Test fun unsortedInputFails() {
        assertFalse(HistoricalDataAudit.inspect(
            listOf(bar(120_000), bar(60_000)), 300_000L).safeForBacktest)
    }
}
