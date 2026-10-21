package com.example.core.backtest

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BacktestLotSizingTest {
    @Test fun acceptsExactMinimumAndMaximum() {
        assertEquals(0.01, BacktestLotSizing.fixedLot(0.01, 0.01, 100.0)!!, 0.0)
        assertEquals(100.0, BacktestLotSizing.fixedLot(100.0, 0.01, 100.0)!!, 0.0)
    }

    @Test fun neverInflatesSmallRequestedVolume() {
        assertNull(BacktestLotSizing.fixedLot(0.001, 0.01, 100.0))
    }

    @Test fun rejectsOversizedOrNonFiniteVolume() {
        assertNull(BacktestLotSizing.fixedLot(101.0, 0.01, 100.0))
        assertNull(BacktestLotSizing.fixedLot(Double.NaN, 0.01, 100.0))
        assertNull(BacktestLotSizing.fixedLot(Double.POSITIVE_INFINITY, 0.01, 100.0))
    }

    @Test fun rejectsInvalidSymbolLimits() {
        assertNull(BacktestLotSizing.fixedLot(0.1, 0.0, 100.0))
        assertNull(BacktestLotSizing.fixedLot(0.1, 1.0, 0.1))
    }
}
