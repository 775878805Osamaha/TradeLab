package com.example.feature.chart

import com.example.core.model.OrderSide
import org.junit.Assert.*
import org.junit.Test

class ChartOrderValidationTest {
    @Test fun buyStopsMustStraddleEntry() {
        assertTrue(ChartOrderValidation.isValid(OrderSide.BUY, 0.1, 100.0, 90.0, 110.0))
        assertFalse(ChartOrderValidation.isValid(OrderSide.BUY, 0.1, 100.0, 101.0, 110.0))
        assertFalse(ChartOrderValidation.isValid(OrderSide.BUY, 0.1, 100.0, 90.0, 99.0))
        assertFalse(ChartOrderValidation.isValid(OrderSide.BUY, 0.1, 100.0, 100.0, null))
    }

    @Test fun sellStopsMustStraddleEntry() {
        assertTrue(ChartOrderValidation.isValid(OrderSide.SELL, 0.1, 100.0, 110.0, 90.0))
        assertFalse(ChartOrderValidation.isValid(OrderSide.SELL, 0.1, 100.0, 99.0, 90.0))
        assertFalse(ChartOrderValidation.isValid(OrderSide.SELL, 0.1, 100.0, 110.0, 101.0))
    }

    @Test fun invalidNumericInputsFailClosed() {
        assertFalse(ChartOrderValidation.isValid(OrderSide.BUY, 0.0, 100.0, null, null))
        assertFalse(ChartOrderValidation.isValid(OrderSide.BUY, Double.NaN, 100.0, null, null))
        assertFalse(ChartOrderValidation.isValid(OrderSide.BUY, 1.0, Double.POSITIVE_INFINITY, null, null))
        assertFalse(ChartOrderValidation.isValid(OrderSide.BUY, 1.0, 100.0, -1.0, null))
        assertFalse(ChartOrderValidation.isValid(OrderSide.SELL, 1.0, 100.0, null, Double.NaN))
    }

    @Test fun lotConstraintsRejectOffStepAndOutOfRange() {
        assertTrue(ChartOrderValidation.isValidLot(0.01, 0.01, 50.0, 0.01))
        assertTrue(ChartOrderValidation.isValidLot(1.25, 0.01, 50.0, 0.01))
        assertFalse(ChartOrderValidation.isValidLot(0.001, 0.01, 50.0, 0.01))
        assertFalse(ChartOrderValidation.isValidLot(50.01, 0.01, 50.0, 0.01))
        assertFalse(ChartOrderValidation.isValidLot(0.015, 0.01, 50.0, 0.01))
        assertFalse(ChartOrderValidation.isValidLot(Double.POSITIVE_INFINITY, 0.01, 50.0, 0.01))
        assertFalse(ChartOrderValidation.isValidLot(1.0, 0.01, 50.0, 0.0))
    }

    @Test fun estimatedRiskIsFiniteAndConservative() {
        assertEquals(100.0, ChartOrderValidation.estimatedLoss(0.1, 100.0, 90.0, 100.0)!!, 0.00001)
        assertNull(ChartOrderValidation.estimatedLoss(0.1, 100.0, null, 100.0))
        assertNull(ChartOrderValidation.estimatedLoss(Double.NaN, 100.0, 90.0, 100.0))
    }
}
