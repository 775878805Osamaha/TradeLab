package com.example.core.market

import com.example.core.model.Timeframe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoricalCsvImporterTest {
    private val header = "timestamp_ms,open,high,low,close,volume\n"

    @Test fun importsAttributedRealMarketCsvWithoutRelabelingAsBinance() {
        val data = header + "900000,100,105,98,104,10\n1800000,104,106,103,105,12"
        val result = HistoricalCsvImporter.parse(data, "XAUUSD", Timeframe.M15, "broker-export")
        assertEquals(2, result.size)
        assertEquals("USER_IMPORTED:broker-export", result[0].source)
        assertEquals(105.0, result[1].close, 0.0)
    }

    @Test fun duplicateTimestampsAreRejected() {
        val data = header + "900000,100,105,98,104,10\n900000,104,106,103,105,12"
        assertFails(data)
    }

    @Test fun invalidOhlcCannotEnterBacktest() {
        assertFails(header + "900000,100,99,98,104,10")
    }

    @Test fun fabricatedProvenanceCannotBeOmitted() {
        try {
            HistoricalCsvImporter.parse(header + "900000,100,105,98,104,10", "XAUUSD", Timeframe.M15, "")
            throw AssertionError("Expected attribution validation")
        } catch (_: IllegalArgumentException) {
            assertTrue(true)
        }
    }

    private fun assertFails(csv: String) {
        try {
            HistoricalCsvImporter.parse(csv, "XAUUSD", Timeframe.M15, "external")
            throw AssertionError("Expected invalid history rejection")
        } catch (_: IllegalArgumentException) {
            assertTrue(true)
        }
    }
}
