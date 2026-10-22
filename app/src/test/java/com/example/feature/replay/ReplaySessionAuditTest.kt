package com.example.feature.replay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReplaySessionAuditTest {
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
