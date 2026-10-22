package com.example.feature.replay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Test

class ReplayRiskPolicyTest {
    private val exposure = ReplayRiskPolicy.Exposure(
        initialBalance = 1000.0,
        balance = 950.0,
        equity = 900.0,
        openPositions = 2,
        pendingOrders = 3,
        consecutiveLosses = 2
    )

    @Test fun disabledGuardAllowsOrders() {
        assertNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(enabled = false, maxPositions = 1), exposure, false))
    }

    @Test fun marketOrderBlockedAtPositionLimit() {
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxPositions = 2), exposure, false))
    }

    @Test fun pendingOrderBlockedAtPendingLimit() {
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxOrders = 3), exposure, true))
    }

    @Test fun drawdownUsesCurrentEquityNotJustRealizedBalance() {
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxDrawdownPercent = 10.0), exposure.copy(openPositions = 0), false))
        assertNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxDrawdownPercent = 11.0), exposure.copy(openPositions = 0), false))
    }

    @Test fun realizedLossLimitIsIndependentFromFloatingEquity() {
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxSessionLossUsd = 50.0), exposure.copy(openPositions = 0), false))
    }

    @Test fun consecutiveLossesStopsAtWinOrBreakeven() {
        assertEquals(2, ReplayRiskPolicy.consecutiveLosses(listOf(12.0, -5.0, -8.0)))
        assertEquals(0, ReplayRiskPolicy.consecutiveLosses(listOf(-5.0, 0.0)))
        assertEquals(1, ReplayRiskPolicy.consecutiveLosses(listOf(-5.0, 2.0, -3.0)))
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxConsecutiveLosses = 2), exposure.copy(openPositions = 0), false))
    }

    @Test fun invalidFinancialDataFailsClosed() {
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(), exposure.copy(equity = Double.NaN), false))
    }
}
