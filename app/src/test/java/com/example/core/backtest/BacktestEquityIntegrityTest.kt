package com.example.core.backtest

import com.example.core.model.EquityPoint
import org.junit.Assert.*
import org.junit.Test

class BacktestEquityIntegrityTest {
    private fun point(time: Long, balance: Double, equity: Double, high: Double) =
        EquityPoint(time, balance, equity, high - equity, high)

    @Test fun acceptsConsistentCurve() {
        BacktestEquityIntegrity.validate(
            listOf(point(100, 100.0, 100.0, 100.0),
                point(200, 100.0, 90.0, 100.0),
                point(300, 110.0, 110.0, 110.0)),
            100.0, 110.0
        )
    }

    @Test fun rejectsDuplicateTimestamps() {
        assertFails { BacktestEquityIntegrity.validate(
            listOf(point(100, 100.0, 100.0, 100.0), point(100, 100.0, 100.0, 100.0)),
            100.0, 100.0
        ) }
    }

    @Test fun rejectsUnreconciledFinalBalance() {
        assertFails { BacktestEquityIntegrity.validate(
            listOf(point(100, 100.0, 100.0, 100.0), point(200, 100.0, 100.0, 100.0)),
            100.0, 120.0
        ) }
    }

    @Test fun rejectsNonFiniteEquity() {
        assertFails { BacktestEquityIntegrity.validate(
            listOf(point(100, 100.0, Double.NaN, 100.0)), 100.0, 100.0
        ) }
    }

    @Test fun emptyCurveCannotHideBalanceChange() {
        BacktestEquityIntegrity.validate(emptyList(), 100.0, 100.0)
        assertFails { BacktestEquityIntegrity.validate(emptyList(), 100.0, 110.0) }
    }

    private fun assertFails(block: () -> Unit) {
        try { block(); fail("Expected integrity validation to fail") }
        catch (_: IllegalArgumentException) {}
    }
}
