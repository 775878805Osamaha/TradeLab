package com.example.feature.chart.model

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChartHistoryEdgePullTest {
    @Test fun shortSeriesCanRequestHistoryDespiteZeroScrollRange() {
        val edge = ChartHistoryEdgePull()
        edge.beginTouch()
        assertFalse(edge.rightPull(20f, 0f, 64f, canRequest = true))
        assertFalse(edge.rightPull(25f, 0f, 64f, canRequest = true))
        assertTrue(edge.rightPull(30f, 0f, 64f, canRequest = true))
        assertFalse(edge.rightPull(100f, 0f, 64f, canRequest = true))
    }

    @Test fun noRequestWhenUserIsPanningInsideLoadedHistory() {
        val edge = ChartHistoryEdgePull()
        edge.beginTouch()
        repeat(20) { assertFalse(edge.rightPull(100f, 100f, 64f, canRequest = true)) }
        assertFalse(edge.rightPull(10f, 20f, 64f, canRequest = true))
    }

    @Test fun networkLoadingBlocksRequestsButANewTouchAllowsRetry() {
        val edge = ChartHistoryEdgePull()
        edge.beginTouch()
        assertFalse(edge.rightPull(80f, 0f, 64f, canRequest = false))
        edge.beginTouch()
        assertTrue(edge.rightPull(80f, 0f, 64f, canRequest = true))
        assertFalse(edge.rightPull(80f, 0f, 64f, canRequest = true))
    }

    @Test fun retreatingFromEdgeResetsThePull() {
        val edge = ChartHistoryEdgePull()
        edge.beginTouch()
        assertFalse(edge.rightPull(60f, 0f, 64f, canRequest = true))
        assertFalse(edge.rightPull(-10f, 0f, 64f, canRequest = true))
        assertFalse(edge.rightPull(30f, 0f, 64f, canRequest = true))
        assertTrue(edge.rightPull(40f, 0f, 64f, canRequest = true))
    }
}
