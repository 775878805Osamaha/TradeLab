package com.example.feature.chart.model

import org.junit.Assert.*
import org.junit.Test

class ChartTimeAxisTest {
    @Test fun firstLabelIncludesDate() {
        assertEquals("01/01 00:00", ChartTimeAxis.label(0L, null))
    }

    @Test fun sameDayUsesCompactTime() {
        assertEquals("01:00", ChartTimeAxis.label(3_600_000L, 0L))
    }

    @Test fun midnightCrossingShowsDate() {
        assertEquals("01/02 00:00", ChartTimeAxis.label(86_400_000L, 86_340_000L))
    }

    @Test fun labelsRemainUtc() {
        assertEquals("01/01 00:00", ChartTimeAxis.label(0L, null))
    }

    @Test fun negativeEpochDayIsCorrect() {
        assertEquals(-1L, ChartTimeAxis.dayKey(-1L))
    }

    @Test fun overlappingLabelsAreHidden() {
        assertFalse(ChartTimeAxis.shouldDisplay(100f, 180f, 600f, 95f))
        assertTrue(ChartTimeAxis.shouldDisplay(200f, 270f, 600f, 180f))
    }

    @Test fun labelsCannotClipViewport() {
        assertFalse(ChartTimeAxis.shouldDisplay(-2f, 50f, 600f, -1000f))
        assertFalse(ChartTimeAxis.shouldDisplay(560f, 610f, 600f, -1000f))
    }

    @Test fun invalidCoordinatesAreHidden() {
        assertFalse(ChartTimeAxis.shouldDisplay(Float.NaN, 20f, 600f, -100f))
    }
}
