package com.example.core.market

import org.junit.Assert.*
import org.junit.Test

class RangeTickCacheCoverageTest {
    private fun s(from: Long, to: Long) = RangeTickCacheCoverage.Span(from, to)
    private val planner = RangeTickCacheCoverage

    @Test fun aCompleteSavedWindowNeedsNoBrokerRequest() {
        assertEquals(listOf(RangeTickCacheCoverage.Piece.Saved(s(10, 100), 25, 75)),
            planner.plan(25, 75, listOf(s(10, 100))))
    }

    @Test fun differentlySizedVerifiedLeavesCoverTheWholeWindowWithoutDuplicates() {
        assertEquals(listOf(
            RangeTickCacheCoverage.Piece.Saved(s(10, 40), 10, 40),
            RangeTickCacheCoverage.Piece.Saved(s(35, 90), 41, 90),
            RangeTickCacheCoverage.Piece.Saved(s(91, 120), 91, 120)
        ), planner.plan(10, 120, listOf(s(91, 120), s(35, 90), s(10, 40))))
    }

    @Test fun onlyRealGapsAreRequestedAfterAnInterruptedHistoryDownload() {
        assertEquals(listOf(
            RangeTickCacheCoverage.Piece.Missing(1, 9),
            RangeTickCacheCoverage.Piece.Saved(s(10, 20), 10, 20),
            RangeTickCacheCoverage.Piece.Missing(21, 29),
            RangeTickCacheCoverage.Piece.Saved(s(30, 50), 30, 50),
            RangeTickCacheCoverage.Piece.Missing(51, 60)
        ), planner.plan(1, 60, listOf(s(30, 50), s(10, 20))))
    }

    @Test fun savedEmptyBidIntervalsAreStillCompleteCoverage() {
        val slices = listOf(s(1, 10), s(11, 20), s(21, 30))
        assertEquals(3, planner.plan(1, 30, slices).size)
        assertTrue(planner.plan(1, 30, slices).all { it is RangeTickCacheCoverage.Piece.Saved })
    }

    @Test fun exactBidQuotesSurviveLosslessCompressionAndSameMillisecondDuplicates() {
        val ticks = listOf(RangePriceTick(1000, 4071.37), RangePriceTick(1000, 4071.38),
            RangePriceTick(1002, 4067.1), RangePriceTick(2000, 4080.0))
        val bytes = RangeTickCacheCodec.encode(ticks, 900, 2100)
        assertEquals(ticks, RangeTickCacheCodec.decode(bytes, 4, 900, 2100))
        assertTrue(RangeTickCacheCodec.decode(RangeTickCacheCodec.encode(emptyList(), 1, 100),
            0, 1, 100).isEmpty())
    }

    @Test fun corruptCountsAndUnverifiedBrokerPricesAreNeverAcceptedAsComplete() {
        val correct = listOf(RangePriceTick(10, 4000.0))
        val bytes = RangeTickCacheCodec.encode(correct, 1, 20)
        assertThrows(IllegalArgumentException::class.java) {
            RangeTickCacheCodec.decode(bytes, 2, 1, 20)
        }
        assertThrows(IllegalArgumentException::class.java) {
            RangeTickCacheCodec.encode(listOf(RangePriceTick(10, 4000.0),
                RangePriceTick(9, 4001.0)), 1, 20)
        }
        assertThrows(IllegalArgumentException::class.java) {
            RangeTickCacheCodec.encode(listOf(RangePriceTick(11, Double.NaN)), 1, 20)
        }
    }
}
