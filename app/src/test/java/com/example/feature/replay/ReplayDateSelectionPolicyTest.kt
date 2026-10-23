package com.example.feature.replay

import org.junit.Assert.*
import org.junit.Test

class ReplayDateSelectionPolicyTest {
    @Test fun historicalDatesAllowedFutureAndNegativeRejected() {
        val now = 1_700_000_000_000L
        assertTrue(ReplayDateSelectionPolicy.isValid(0L, now))
        assertTrue(ReplayDateSelectionPolicy.isValid(now, now))
        assertFalse(ReplayDateSelectionPolicy.isValid(-1L, now))
        assertFalse(ReplayDateSelectionPolicy.isValid(now + 1L, now))
    }

    @Test fun noDataAppearsOnlyAfterLoadFinishes() {
        assertFalse(ReplayDateSelectionPolicy.shouldShowNoData(true, 0))
        assertTrue(ReplayDateSelectionPolicy.shouldShowNoData(false, 0))
        assertFalse(ReplayDateSelectionPolicy.shouldShowNoData(false, 20))
    }
}
