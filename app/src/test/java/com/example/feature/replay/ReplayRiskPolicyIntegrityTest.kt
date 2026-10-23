package com.example.feature.replay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class ReplayRiskPolicyIntegrityTest {
    private val valid = ReplayRiskPolicy.Exposure(
        initialBalance = 1000.0, balance = 1000.0, equity = 1000.0,
        openPositions = 0, pendingOrders = 0, consecutiveLosses = 0
    )

    @Test fun disabledRiskGuardStillRejectsCorruptEquity() {
        val limits = ReplayRiskPolicy.Limits(enabled = false)
        assertNotNull(ReplayRiskPolicy.blockReason(limits, valid.copy(equity = Double.NaN), false))
        assertNotNull(ReplayRiskPolicy.blockReason(limits, valid.copy(balance = Double.POSITIVE_INFINITY), false))
        assertNotNull(ReplayRiskPolicy.blockReason(limits, valid.copy(initialBalance = 0.0), false))
        assertNotNull(ReplayRiskPolicy.blockReason(limits, valid.copy(openPositions = -1), false))
        assertNotNull(ReplayRiskPolicy.blockReason(limits, valid.copy(pendingOrders = -1), true))
        assertNotNull(ReplayRiskPolicy.blockReason(limits, valid.copy(consecutiveLosses = -1), false))
    }

    @Test fun disablingRiskLimitsStillAllowsValidAccount() {
        assertNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(enabled = false, maxPositions = 1),
            valid.copy(openPositions = 100), false
        ))
    }

    @Test fun enabledLimitsRejectInvalidConfiguration() {
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxSessionLossUsd = Double.NaN), valid, false))
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxDrawdownPercent = -1.0), valid, false))
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxPositions = 0), valid, false))
    }

    @Test fun pendingAndMarketCapacityAreIndependent() {
        val limits = ReplayRiskPolicy.Limits(maxPositions = 2, maxOrders = 3)
        assertNotNull(ReplayRiskPolicy.blockReason(limits, valid.copy(openPositions = 2), false))
        assertNull(ReplayRiskPolicy.blockReason(limits, valid.copy(openPositions = 2), true))
        assertNotNull(ReplayRiskPolicy.blockReason(limits, valid.copy(pendingOrders = 3), true))
        assertNull(ReplayRiskPolicy.blockReason(limits, valid.copy(pendingOrders = 3), false))
    }

    @Test fun drawdownRiskHandlesVeryLargeFiniteBalances() {
        val huge = valid.copy(
            initialBalance = 1.0e307, balance = 1.0e307, equity = 5.0e306
        )
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxDrawdownPercent = 40.0), huge, false
        ))
        assertNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxDrawdownPercent = 60.0), huge, false
        ))
    }

    @Test fun negativeEquityBlocksFurtherTradingAtDrawdownLimit() {
        assertNotNull(ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(maxDrawdownPercent = 100.0),
            valid.copy(equity = -10.0), false
        ))
    }

    @Test fun consecutiveLossCounterStopsAtNonLoss() {
        assertEquals(2, ReplayRiskPolicy.consecutiveLosses(listOf(-5.0, 0.0, -2.0, -1.0)))
        assertEquals(0, ReplayRiskPolicy.consecutiveLosses(listOf(-1.0, 1.0)))
    }
}
