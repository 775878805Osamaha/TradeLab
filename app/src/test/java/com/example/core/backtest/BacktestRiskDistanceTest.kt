package com.example.core.backtest

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BacktestRiskDistanceTest {
    @Test fun buyUsesAskAndSellUsesBid() {
        assertEquals(12.0, BacktestRiskDistance.pips(true, 100.0, 100.2, 99.0, 0.1)!!, 1e-9)
        assertEquals(10.0, BacktestRiskDistance.pips(false, 100.0, 100.2, 101.0, 0.1)!!, 1e-9)
    }

    @Test fun rejectsStopsOnWrongSide() {
        assertNull(BacktestRiskDistance.pips(true, 100.0, 100.2, 100.3, 0.1))
        assertNull(BacktestRiskDistance.pips(false, 100.0, 100.2, 99.9, 0.1))
    }

    @Test fun rejectsInvalidPricesAndPipSize() {
        assertNull(BacktestRiskDistance.pips(true, 100.0, 100.2, Double.NaN, 0.1))
        assertNull(BacktestRiskDistance.pips(true, 100.0, 100.2, 99.0, 0.0))
    }

    @Test fun retainsFallbackWithoutStop() {
        assertEquals(25.0, BacktestRiskDistance.pips(true, 100.0, 100.2, null, 0.1)!!, 0.0)
    }
}
