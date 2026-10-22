package com.example.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

class ChartPriceRangeIndexTest {
    @Test fun emptyIndexUsesSafeRange() {
        assertEquals(0.0 to 1.0, ChartPriceRangeIndex(emptyList()).query(0, 1))
    }
}
