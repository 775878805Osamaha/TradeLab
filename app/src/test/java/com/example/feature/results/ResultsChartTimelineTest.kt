package com.example.feature.results

import org.junit.Assert.*
import org.junit.Test

class ResultsChartTimelineTest {
    @Test fun irregularObservationsUseElapsedTimeRatherThanEventIndex() {
        val axis = ResultsChartTimeline(listOf(1000L, 1100L, 2000L))
        assertEquals(.1, axis.fraction(1100L), 0.0)
        assertEquals(1500L, axis.timeAt(.5))
        assertEquals(1, axis.nearest(.2))
        assertEquals(2, axis.nearest(.8))
    }

    @Test fun duplicateTimestampSelectsLatestExecutionAndDoesNotInventTime() {
        val axis = ResultsChartTimeline(listOf(1000L, 1000L, 2000L))
        assertEquals(0.0, axis.fraction(1000L), 0.0)
        assertEquals(1, axis.nearest(0.0))
        assertEquals(2, axis.nearest(2.0))
    }

    @Test fun emptyAndSingleInstantHaveSafeHitTesting() {
        assertNull(ResultsChartTimeline(emptyList()).nearest(.5))
        val axis = ResultsChartTimeline(listOf(1000L, 1000L))
        assertEquals(.5, axis.fraction(1000L), 0.0)
        assertEquals(1000L, axis.timeAt(.9))
        assertEquals(1, axis.nearest(.1))
    }
}
