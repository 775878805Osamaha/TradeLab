package com.example.core.execution

import com.example.core.model.ExitReason
import com.example.core.model.Position
import com.example.core.model.PositionSide
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertNull
import org.junit.Test

class ExecutionCloseIntegrityTest {
    private val engine = ExecutionEngine()
    private fun position(
        entry: Double = 2000.0, volume: Double = 0.10,
        commission: Double = 5.0, swap: Double = 2.0,
        margin: Double = 200.0
    ) = Position(
        accountId = 9999, symbol = "XAUUSD", side = PositionSide.BUY,
        volume = volume, entryPrice = entry, currentPrice = entry,
        stopLoss = 1990.0, openTime = 1L, profitLoss = 0.0,
        commission = commission, swap = swap, margin = margin
    )

    @Test fun fullCloseRealizesNetProfitWithoutRefundingMarginIntoProfit() {
        val (journal, remainder) = engine.closePosition(
            position(), 2010.0, ExitReason.MANUAL_CLOSE, closeTime = 2L)
        assertNull(remainder)
        assertEquals(100.0, journal.profitLoss, 1e-8)
        assertEquals(5.0, journal.commission, 1e-8)
        assertEquals(2.0, journal.swap, 1e-8)
        assertEquals(93.0, journal.netProfitLoss, 1e-8)
    }

    @Test fun partialClosePreservesRemainingCollateralAndCostBasis() {
        val (journal, remainder) = engine.closePosition(
            position(), 2010.0, ExitReason.MANUAL_CLOSE,
            closeTime = 2L, partialVolume = 0.04)
        assertEquals(40.0, journal.profitLoss, 1e-8)
        assertEquals(2.0, journal.commission, 1e-8)
        assertEquals(0.8, journal.swap, 1e-8)
        requireNotNull(remainder)
        assertEquals(0.06, remainder.volume, 1e-8)
        assertEquals(120.0, remainder.margin, 1e-8)
        assertEquals(3.0, remainder.commission, 1e-8)
        assertEquals(1.2, remainder.swap, 1e-8)
    }

    @Test fun closeRejectsCorruptEntryAndCosts() {
        assertThrows(IllegalArgumentException::class.java) {
            engine.closePosition(position(entry = Double.NaN), 2010.0, ExitReason.MANUAL_CLOSE)
        }
        assertThrows(IllegalArgumentException::class.java) {
            engine.closePosition(position(commission = -1.0), 2010.0, ExitReason.MANUAL_CLOSE)
        }
        assertThrows(IllegalArgumentException::class.java) {
            engine.closePosition(position(margin = Double.POSITIVE_INFINITY), 2010.0, ExitReason.MANUAL_CLOSE)
        }
    }

    @Test fun closeRejectsOverflowedGrossProfitAndNetProfit() {
        assertThrows(IllegalArgumentException::class.java) {
            engine.closePosition(position(entry = 1.0e308, volume = 1.0e308),
                1.0, ExitReason.MANUAL_CLOSE)
        }
        assertThrows(IllegalArgumentException::class.java) {
            engine.closePosition(position(commission = 1.0e308, swap = 1.0e308),
                2010.0, ExitReason.MANUAL_CLOSE)
        }
    }

    @Test fun invalidPartialCloseCannotMutatePosition() {
        assertThrows(IllegalArgumentException::class.java) {
            engine.closePosition(position(), 2010.0, ExitReason.MANUAL_CLOSE, partialVolume = 0.11)
        }
        assertThrows(IllegalArgumentException::class.java) {
            engine.closePosition(position(), 2010.0, ExitReason.MANUAL_CLOSE, partialVolume = 0.0)
        }
    }
}
