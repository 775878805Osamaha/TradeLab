package com.example.core.market

import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class HistoricalCsvFutureSafetyTest {
    private val header = "timestamp_ms,open,high,low,close,volume\n"

    @Test fun futureCandleIsRejected() {
        val interval = 60_000L
        val future = (System.currentTimeMillis() / interval + 10L) * interval
        val csv = header + "$future,100,105,98,104,10"
        try {
            HistoricalCsvImporter.parse(csv, "XAUUSD", Timeframe.M1, "test")
            fail("Expected future bar rejection")
        } catch (_: IllegalArgumentException) {
            assertTrue(true)
        }
    }

    @Test fun unfinishedCurrentCandleIsRejected() {
        val interval = 60_000L
        val currentOpen = (System.currentTimeMillis() / interval) * interval
        val csv = header + "$currentOpen,100,105,98,104,10"
        try {
            HistoricalCsvImporter.parse(csv, "XAUUSD", Timeframe.M1, "test")
            fail("Expected unfinished bar rejection")
        } catch (_: IllegalArgumentException) {
            assertTrue(true)
        }
    }

    @Test fun closedHistoricalBarIsAccepted() {
        val interval = 60_000L
        val oldOpen = (System.currentTimeMillis() / interval - 3L) * interval
        val csv = header + "$oldOpen,100,105,98,104,10"
        assertEquals(1, HistoricalCsvImporter.parse(csv, "XAUUSD", Timeframe.M1, "test").size)
    }
}
