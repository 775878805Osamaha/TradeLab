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
    @Test fun financialTimelineRoundTripRestoresBalanceEquityAndOpenPositions() {
        val initialBalance = 100.0
        val original = listOf(position(1, -2.5))
        val atOpen = ReplayAccountMath.equity(initialBalance, original)
        assertEquals(97.5, atOpen, 0.000001)

        // The replay candle closes position 1 at a realized loss and leaves
        // a second position floating in profit.
        val afterCloseBalance = ReplayAccountMath.realizedBalance(initialBalance, -2.5)
        val remaining = listOf(position(2, 7.0))
        val afterCloseEquity = ReplayAccountMath.equity(afterCloseBalance, remaining)
        assertEquals(97.5, afterCloseBalance, 0.000001)
        assertEquals(104.5, afterCloseEquity, 0.000001)

        // Rewinding restores the previous immutable financial checkpoint.
        val restoredBalance = initialBalance
        val restoredPositions = original.toList()
        assertEquals(100.0, restoredBalance, 0.000001)
        assertEquals(atOpen, ReplayAccountMath.equity(restoredBalance, restoredPositions), 0.000001)

        // Replaying the same close once must produce identical settled values,
        // not apply the loss to the already-settled future balance.
        val replayedBalance = ReplayAccountMath.realizedBalance(restoredBalance, -2.5)
        assertEquals(afterCloseBalance, replayedBalance, 0.000001)
        assertEquals(afterCloseEquity, ReplayAccountMath.equity(replayedBalance, remaining), 0.000001)
    }

    @Test fun settlingSeveralTradesDoesNotIncludeRealizedPnlAsFloatingPnl() {
        val initialBalance = 50.0
        val afterWin = ReplayAccountMath.realizedBalance(initialBalance, 12.0)
        val afterLoss = ReplayAccountMath.realizedBalance(afterWin, -3.0)
        assertEquals(59.0, afterLoss, 0.000001)
        assertEquals(59.0, ReplayAccountMath.equity(afterLoss, emptyList()), 0.000001)
        assertEquals(61.0, ReplayAccountMath.equity(afterLoss, listOf(position(3, 2.0))), 0.000001)
    }

    @Test fun actualExecutionCloseSettlesCommissionAndRestoresReplayBalance() {
        val execution = com.example.core.execution.ExecutionEngine(
            com.example.core.execution.ExecutionConfig(
                slippagePips = 0.0, defaultCommissionPerLot = 5.0
            )
        )
        val opened = execution.executeMarketOrder(
            account = com.example.core.model.VirtualAccount(
                id = 9999L, name = "Replay", balance = 1000.0,
                equity = 1000.0, freeMargin = 1000.0
            ),
            symbol = "XAUUSD",
            side = com.example.core.model.OrderSide.BUY,
            volume = 0.01,
            tick = com.example.core.model.Tick(symbol = "XAUUSD", bid = 2650.0, ask = 2650.25),
            stopLoss = 2640.0, takeProfit = 2670.0,
            mode = "REPLAY"
        )
        assertTrue(opened is com.example.core.execution.ExecutionResult.Success)
        val position = (opened as com.example.core.execution.ExecutionResult.Success).position
        val (trade, remainder) = execution.closePosition(
            position, exitPrice = 2660.25,
            exitReason = com.example.core.model.ExitReason.MANUAL_CLOSE,
            closeTime = 1_700_000_000_000L
        )
        assertNull(remainder)
        assertEquals(10.0, trade.profitLoss, 0.000001)
        assertEquals(0.05, trade.commission, 0.000001)
        assertEquals(9.95, trade.netProfitLoss, 0.000001)
        val balance = ReplayAccountMath.realizedBalance(1000.0, trade.netProfitLoss)
        assertEquals(1009.95, balance, 0.000001)
        assertEquals(balance, ReplayAccountMath.equity(balance, emptyList()), 0.000001)
        // A financial rollback restores the original balance. Re-settling
        // the same historical trade must yield the same result, not double profit.
        val replayed = ReplayAccountMath.realizedBalance(1000.0, trade.netProfitLoss)
        assertEquals(balance, replayed, 0.000001)
    }

}
