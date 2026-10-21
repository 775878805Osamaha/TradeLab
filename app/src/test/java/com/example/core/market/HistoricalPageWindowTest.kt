package com.example.core.market

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HistoricalPageWindowTest {
    @Test fun unalignedStartAndSingleCandlePage() {
        assertEquals(120_000L, HistoricalPageWindow.end(90_000, 240_000, 60_000, 1))
    }

    @Test fun respectsPageSizeAndRequestedEnd() {
        assertEquals(180_000L, HistoricalPageWindow.end(90_000, 240_000, 60_000, 2))
        assertEquals(240_000L, HistoricalPageWindow.end(90_000, 240_000, 60_000, 100))
    }

    @Test fun noOpeningCandleWithinRequestedRange() {
        assertNull(HistoricalPageWindow.end(90_000, 110_000, 60_000, 1))
    }

    @Test fun weeklyBarsStartOnMondayUtc() {
        val week = 604_800_000L
        val monday = 345_600_000L
        assertEquals(monday + week, HistoricalPageWindow.end(
            monday + 1, monday + 2 * week, week, 1))
    }

    @Test fun largeTimestampsDoNotOverflow() {
        assertEquals(Long.MAX_VALUE - 1L, HistoricalPageWindow.end(
            Long.MAX_VALUE - 1L, Long.MAX_VALUE, 1L, 1000))
    }
}
