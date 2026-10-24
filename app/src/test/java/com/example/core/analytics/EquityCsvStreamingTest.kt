package com.example.core.analytics

import org.junit.Assert.*
import org.junit.Test

class EquityCsvStreamingTest {
    private fun p(time: Long, equity: Double) = EquityAnalytics.Point(time, equity)

    @Test fun streamingMatchesLegacyExport() {
        val points = listOf(p(1000, 100.0), p(2000, 120.0), p(3000, 90.0))
        val sink = StringBuilder()
        EquityCsvExporter.write(points, sink)
        assertEquals(EquityCsvExporter.export(points), sink.toString())
    }

    @Test fun streamingEmptySeriesProducesOnlyHeader() {
        val sink = StringBuilder()
        EquityCsvExporter.write(emptyList(), sink)
        assertEquals(EquityCsvExporter.export(emptyList()), sink.toString())
    }

    @Test fun streamingRejectsInvalidPointsBeforeWriting() {
        val sink = StringBuilder()
        try {
            EquityCsvExporter.write(listOf(p(1000, 100.0), p(1000, 110.0)), sink)
            fail("Expected validation failure")
        } catch (_: IllegalArgumentException) {}
        assertEquals("", sink.toString())
    }

    @Test fun largeSeriesProducesExactRowCount() {
        val points = (0 until 10_000).map { p(it.toLong(), 100.0 + it * 0.01) }
        var rows = 0
        val sink = object : Appendable {
            override fun append(csq: CharSequence?): Appendable {
                rows += csq?.count { it == '\n' } ?: 0
                return this
            }
            override fun append(csq: CharSequence?, start: Int, end: Int): Appendable {
                rows += csq?.subSequence(start, end)?.count { it == '\n' } ?: 0
                return this
            }
            override fun append(c: Char): Appendable {
                if (c == '\n') rows++
                return this
            }
        }
        EquityCsvExporter.write(points, sink)
        assertEquals(10_001, rows)
    }
}
