package com.example.history

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoryIntegrityAuditTest {
    private fun bar(t: Long) = HistoryIntegrityAudit.Bar(t, 100.0, 102.0, 99.0, 101.0, 10.0)

    @Test fun cleanBars() {
        val report = HistoryIntegrityAudit.inspect(listOf(bar(0), bar(60000)), 60000, 120000)
        assertTrue(report.clean)
        assertEquals(2, report.accepted.size)
    }

    @Test fun gapNotFilled() {
        val report = HistoryIntegrityAudit.inspect(listOf(bar(0), bar(180000)), 60000, 240000)
        assertEquals(2L, report.missingIntervals)
        assertEquals(2, report.accepted.size)
    }

    @Test fun duplicateRejected() {
        val report = HistoryIntegrityAudit.inspect(listOf(bar(0), bar(0)), 60000, 120000)
        assertEquals(1, report.accepted.size)
        assertEquals(HistoryIntegrityAudit.Problem.DUPLICATE_TIME, report.findings.single().problem)
    }

    @Test fun futureExcluded() {
        val report = HistoryIntegrityAudit.inspect(listOf(bar(120000)), 60000, 90000)
        assertEquals(0, report.accepted.size)
    }
}
