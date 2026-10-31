package com.example.history

import org.junit.Assert.*
import org.junit.Test

class ReplayHistoryWindowTest {
    private fun bar(t: Long) = HistoryIntegrityAudit.Bar(t, 100.0, 102.0, 99.0, 101.0, 1.0)
    private fun report() = HistoryIntegrityAudit.inspect(
        listOf(bar(0), bar(60_000), bar(120_000)), 60_000, 180_000
    )

    @Test fun startsWithoutFutureBars() {
        val window = ReplayHistoryWindow.fromValidated(report(), initialVisible = 1)
        assertEquals(1, window.size)
        assertEquals(0L, window.latest!!.openTimeMillis)
        assertEquals(1, window.last(100).size)
    }

    @Test fun advanceAndRewindAreBounded() {
        val start = ReplayHistoryWindow.fromValidated(report())
        assertTrue(start.isEmpty)
        val end = start.advance(100)
        assertEquals(3, end.size)
        assertEquals(1, end.rewind(2).size)
        assertTrue(end.rewind(100).isEmpty)
        assertTrue(start.isEmpty)
    }

    @Test fun rejectsHistoryWithGapsByDefault() {
        val gaps = HistoryIntegrityAudit.inspect(listOf(bar(0), bar(120_000)), 60_000, 180_000)
        var rejected = false
        try {
            ReplayHistoryWindow.fromValidated(gaps)
        } catch (_: IllegalArgumentException) {
            rejected = true
        }
        assertTrue(rejected)
        assertEquals(2, ReplayHistoryWindow.fromValidated(gaps, 2, rejectFindings = false).size)
    }

    @Test fun visibleSnapshotIsIndependent() {
        val window = ReplayHistoryWindow.fromValidated(report(), 2)
        val snapshot = window.visibleBars()
        assertEquals(2, snapshot.size)
        assertEquals(3, window.advance().size)
        assertEquals(2, snapshot.size)
    }
}
