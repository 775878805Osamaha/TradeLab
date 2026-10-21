package com.example

import com.example.core.execution.PositionEvaluation
import com.example.core.market.DefaultSymbols
import com.example.core.model.*
import com.example.core.replay.HistoricalReplayEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.*
import org.junit.Test

class ReplaySpreadEquityTests {
    private val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
    private val candle = Candle(
        symbol = "BTCUSDT", timeframe = Timeframe.M15,
        openTime = 1_700_000_000_000L,
        open = 100.0, high = 110.0, low = 90.0, close = 100.0
    )
    private fun position(side: PositionSide) = Position(
        id = 1L, accountId = 1L, symbol = "BTCUSDT", side = side,
        volume = 0.01, entryPrice = 100.0, currentPrice = 100.0
    )

    @Test fun buyFloatingPnlUsesBidNotMidpoint() {
        val sym = DefaultSymbols.getSymbol("BTCUSDT")
        val expectedBid = candle.close - sym.defaultSpreadPips * sym.pipSize / 2.0
        val result = engine.evaluatePositionConservative(position(PositionSide.BUY), candle)
        assertTrue(result is PositionEvaluation.KeepOpen)
        val updated = (result as PositionEvaluation.KeepOpen).updatedPosition
        assertEquals(expectedBid, updated.currentPrice, 0.000001)
        assertEquals((expectedBid - 100.0) * 0.01 * sym.contractSize, updated.profitLoss, 0.000001)
    }

    @Test fun sellFloatingPnlUsesAskNotMidpoint() {
        val sym = DefaultSymbols.getSymbol("BTCUSDT")
        val expectedAsk = candle.close + sym.defaultSpreadPips * sym.pipSize / 2.0
        val result = engine.evaluatePositionConservative(position(PositionSide.SELL), candle)
        assertTrue(result is PositionEvaluation.KeepOpen)
        val updated = (result as PositionEvaluation.KeepOpen).updatedPosition
        assertEquals(expectedAsk, updated.currentPrice, 0.000001)
        assertEquals((100.0 - expectedAsk) * 0.01 * sym.contractSize, updated.profitLoss, 0.000001)
    }
}
