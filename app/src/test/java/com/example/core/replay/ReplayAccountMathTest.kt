package com.example.core.replay

import com.example.core.model.Position
import com.example.core.model.PositionSide
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ReplayAccountMathTest {
    private fun position(margin: Double, floating: Double = 0.0) = Position(
        accountId = 9999, symbol = "XAUUSD", side = PositionSide.BUY,
        volume = 0.01, entryPrice = 2000.0, currentPrice = 2000.0,
        openTime = 0L, profitLoss = floating, swap = 0.0,
        commission = 0.0, margin = margin
    )

    @Test fun marginIsCollateralNotRealizedLoss() {
        val positions = listOf(position(250.0, -40.0), position(100.0, 10.0))
        assertEquals(970.0, ReplayAccountMath.equity(1000.0, positions), 0.0)
        assertEquals(350.0, ReplayAccountMath.usedMargin(positions), 0.0)
        assertEquals(620.0, ReplayAccountMath.freeMargin(1000.0, positions), 0.0)
    }

    @Test fun freeMarginNeverGoesNegative() {
        val positions = listOf(position(1200.0, -100.0))
        assertEquals(900.0, ReplayAccountMath.equity(1000.0, positions), 0.0)
        assertEquals(0.0, ReplayAccountMath.freeMargin(1000.0, positions), 0.0)
    }

    @Test fun closingPositionReleasesCollateralAndRealizesOnlyNetProfit() {
        val open = listOf(position(300.0, 50.0))
        assertEquals(750.0, ReplayAccountMath.freeMargin(1000.0, open), 0.0)
        val settledBalance = ReplayAccountMath.realizedBalance(1000.0, 45.0)
        assertEquals(1045.0, settledBalance, 0.0)
        assertEquals(1045.0, ReplayAccountMath.freeMargin(settledBalance, emptyList()), 0.0)
    }

    @Test fun invalidMarginCannotCreateFreeFunds() {
        for (margin in listOf(-1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertThrows(IllegalArgumentException::class.java) {
                ReplayAccountMath.usedMargin(listOf(position(margin)))
            }
        }
    }

    @Test fun invalidFloatingPnlCannotCorruptEquity() {
        assertThrows(IllegalArgumentException::class.java) {
            ReplayAccountMath.equity(1000.0, listOf(position(10.0, Double.NaN)))
        }
    }

    @Test fun underwaterAccountWithExtremeFiniteNumbersHasZeroFreeMargin() {
        val positions = listOf(position(1.0e308, -1.0e308))
        assertEquals(0.0, ReplayAccountMath.freeMargin(-1.0e308, positions), 0.0)
    }

    @Test fun exactCollateralBoundaryHasZeroFreeMargin() {
        val positions = listOf(position(1000.0))
        assertEquals(0.0, ReplayAccountMath.freeMargin(1000.0, positions), 0.0)
    }

    @Test fun emptyAccountPreservesInitialFunds() {
        assertEquals(1000.0, ReplayAccountMath.equity(1000.0, emptyList()), 0.0)
        assertEquals(0.0, ReplayAccountMath.usedMargin(emptyList()), 0.0)
        assertEquals(1000.0, ReplayAccountMath.freeMargin(1000.0, emptyList()), 0.0)
    }
}
