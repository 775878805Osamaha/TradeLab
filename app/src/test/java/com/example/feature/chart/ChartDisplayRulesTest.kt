package com.example.feature.chart

import org.junit.Assert.*
import org.junit.Test

class ChartDisplayRulesTest {
    @Test fun missingHistoryShowsNoDataButLoadingDoesNot() {
        assertTrue(ChartDisplayRules.showNoData(isLoading = false, candleCount = 0))
        assertFalse(ChartDisplayRules.showNoData(isLoading = true, candleCount = 0))
        assertFalse(ChartDisplayRules.showNoData(isLoading = false, candleCount = 1))
    }

    @Test fun dateSelectionRequiresLoadedHistoryAndValidDate() {
        val selectedDate = 1_700_000_000_000L
        assertEquals(selectedDate, ChartDisplayRules.selectedReplayTimestamp(selectedDate, false, 100))
        assertNull(ChartDisplayRules.selectedReplayTimestamp(selectedDate, true, 100))
        assertNull(ChartDisplayRules.selectedReplayTimestamp(selectedDate, false, 0))
        assertNull(ChartDisplayRules.selectedReplayTimestamp(null, false, 100))
        assertNull(ChartDisplayRules.selectedReplayTimestamp(-1L, false, 100))
    }
}
