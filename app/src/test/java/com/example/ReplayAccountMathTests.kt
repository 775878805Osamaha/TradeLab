package com.example

import com.example.core.model.Position
import com.example.core.model.PositionSide
import com.example.core.replay.ReplayAccountMath
import org.junit.Assert.*
import org.junit.Test

class ReplayAccountMathTests {
    private fun position(id: Long, pnl: Double) = Position(
        id = id, accountId = 9999L, symbol = "BTCUSDT",
        side = PositionSide.BUY, volume = 0.01,
        entryPrice = 100.0, currentPrice = 100.0, profitLoss = pnl
    )

    @Test fun equityIncludesProfitsAndLossesOfMultiplePositions() {
        val positions = listOf(position(1, 12.5), position(2, -4.0), position(3, 1.5))
        assertEquals(110.0, ReplayAccountMath.equity(100.0, positions), 0.000001)
    }

    @Test fun realizedProfitMovesBalanceWithoutDoubleCountingFloatingPnl() {
        val before = listOf(position(1, 12.5), position(2, -4.0))
        assertEquals(108.5, ReplayAccountMath.equity(100.0, before), 0.000001)
        val balanceAfterClose = ReplayAccountMath.realizedBalance(100.0, 12.5)
        assertEquals(112.5, balanceAfterClose, 0.000001)
        assertEquals(108.5, ReplayAccountMath.equity(balanceAfterClose, listOf(before[1])), 0.000001)
    }

    @Test fun closingLosingPositionKeepsEquityConsistent() {
        val balance = ReplayAccountMath.realizedBalance(100.0, -7.25)
        assertEquals(92.75, balance, 0.000001)
        assertEquals(92.75, ReplayAccountMath.equity(balance, emptyList()), 0.000001)
    }

    @Test fun rejectsNonFiniteBalanceAndRealizedPnl() {
        assertThrows(IllegalArgumentException::class.java) { ReplayAccountMath.equity(Double.NaN, emptyList()) }
        assertThrows(IllegalArgumentException::class.java) { ReplayAccountMath.realizedBalance(100.0, Double.POSITIVE_INFINITY) }
    }

    @Test fun rejectsNonFiniteFloatingPnl() {
        assertThrows(IllegalArgumentException::class.java) {
            ReplayAccountMath.equity(100.0, listOf(position(1, Double.NaN)))
        }
    }

    @Test fun rejectsArithmeticOverflow() {
        assertThrows(IllegalArgumentException::class.java) {
            ReplayAccountMath.realizedBalance(Double.MAX_VALUE, Double.MAX_VALUE)
        }
    }
}
