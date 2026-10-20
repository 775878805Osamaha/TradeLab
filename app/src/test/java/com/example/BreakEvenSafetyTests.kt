package com.example

import com.example.core.execution.*
import com.example.core.model.*
import org.junit.Assert.*
import org.junit.Test

class BreakEvenSafetyTests {
    private val engine = ExecutionEngine()
    private fun position(side: PositionSide) = Position(
        id = 1L, accountId = 1L, symbol = "BTCUSDT", side = side,
        volume = 0.01, entryPrice = 100.0, currentPrice = 100.0
    )
    private fun tick(bid: Double, ask: Double, symbol: String = "BTCUSDT") =
        Tick(symbol = symbol, bid = bid, ask = ask)

    @Test fun rejectsCrossSymbolTick() {
        assertTrue(engine.calculateBreakEven(position(PositionSide.BUY), tick(110.0, 110.2, "ETHUSDT")).isFailure)
    }

    @Test fun rejectsInvalidProtectionOffset() {
        assertTrue(engine.calculateBreakEven(position(PositionSide.BUY), tick(110.0, 110.2), Double.NaN).isFailure)
        assertTrue(engine.calculateBreakEven(position(PositionSide.BUY), tick(110.0, 110.2), -1.0).isFailure)
    }

    @Test fun buyProtectionCannotCrossCurrentBid() {
        assertTrue(engine.calculateBreakEven(position(PositionSide.BUY), tick(100.1, 100.2), 1e12).isFailure)
    }

    @Test fun sellProtectionCannotCrossCurrentAsk() {
        assertTrue(engine.calculateBreakEven(position(PositionSide.SELL), tick(99.8, 99.9), 1e12).isFailure)
    }

    @Test fun buyBreakEvenIsBetweenEntryAndBid() {
        val result = engine.calculateBreakEven(position(PositionSide.BUY), tick(110.0, 110.2), 1.0)
        assertTrue(result.isSuccess)
        assertTrue(result.getOrThrow() >= 100.0)
        assertTrue(result.getOrThrow() < 110.0)
    }

    @Test fun sellBreakEvenIsBetweenAskAndEntry() {
        val result = engine.calculateBreakEven(position(PositionSide.SELL), tick(89.8, 90.0), 1.0)
        assertTrue(result.isSuccess)
        assertTrue(result.getOrThrow() <= 100.0)
        assertTrue(result.getOrThrow() > 90.0)
    }
}
