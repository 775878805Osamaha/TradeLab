package com.example

import com.example.core.execution.*
import com.example.core.model.*
import org.junit.Assert.*
import org.junit.Test

class TrailingStopSafetyTests {
    private val engine = ExecutionEngine()
    private fun position(side: PositionSide, distance: Double) = Position(
        id = 1L, accountId = 1L, symbol = "BTCUSDT", side = side,
        volume = 0.01, entryPrice = 100.0, currentPrice = 100.0,
        trailingStopDistance = distance
    )
    private fun tick(bid: Double = 110.0, ask: Double = 110.2, symbol: String = "BTCUSDT") =
        Tick(symbol = symbol, bid = bid, ask = ask)

    @Test fun rejectsMismatchedQuote() {
        assertNull(engine.calculateTrailingStopUpdate(position(PositionSide.BUY, 5.0), tick(symbol = "ETHUSDT")))
    }

    @Test fun rejectsNonFiniteTrailingDistance() {
        assertNull(engine.calculateTrailingStopUpdate(position(PositionSide.BUY, Double.NaN), tick()))
        assertNull(engine.calculateTrailingStopUpdate(position(PositionSide.SELL, Double.POSITIVE_INFINITY), tick()))
    }

    @Test fun rejectsInvalidTrailingStep() {
        assertNull(engine.calculateTrailingStopUpdate(position(PositionSide.BUY, 5.0), tick(), Double.NaN))
        assertNull(engine.calculateTrailingStopUpdate(position(PositionSide.BUY, 5.0), tick(), 0.0))
    }

    @Test fun neverSetsNegativeStopOnBuy() {
        assertNull(engine.calculateTrailingStopUpdate(position(PositionSide.BUY, 500.0), tick()))
    }

    @Test fun buyTrailingStopStillMovesUp() {
        assertEquals(105.0, engine.calculateTrailingStopUpdate(position(PositionSide.BUY, 5.0), tick())!!, 0.0001)
    }

    @Test fun sellTrailingStopStillMovesDown() {
        assertEquals(115.2, engine.calculateTrailingStopUpdate(position(PositionSide.SELL, 5.0), tick())!!, 0.0001)
    }
}
