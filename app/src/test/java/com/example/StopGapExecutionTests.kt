package com.example

import com.example.core.execution.*
import com.example.core.model.*
import org.junit.Assert.*
import org.junit.Test

class StopGapExecutionTests {
    private val engine = ExecutionEngine(ExecutionConfig(slippagePips = 0.0))
    private fun position(side: PositionSide, stop: Double) = Position(
        id = 1L, accountId = 1L, symbol = "BTCUSDT", side = side,
        volume = 0.01, entryPrice = 100.0, currentPrice = 100.0,
        stopLoss = stop
    )
    private fun candle(open: Double, high: Double, low: Double, close: Double) = Candle(
        symbol = "BTCUSDT", timeframe = Timeframe.M1, openTime = 1000L,
        closeTime = 61000L, open = open, high = high, low = low, close = close
    )

    @Test fun buyStopGapDownOnTickFillsAtWorseBid() {
        val result = engine.evaluatePositionOnTick(
            position(PositionSide.BUY, 95.0),
            Tick(symbol = "BTCUSDT", bid = 90.0, ask = 90.2)
        )
        assertTrue(result is PositionEvaluation.TriggerClose)
        assertEquals(90.0, (result as PositionEvaluation.TriggerClose).exitPrice, 0.0001)
    }

    @Test fun sellStopGapUpOnTickFillsAtWorseAsk() {
        val result = engine.evaluatePositionOnTick(
            position(PositionSide.SELL, 105.0),
            Tick(symbol = "BTCUSDT", bid = 109.8, ask = 110.0)
        )
        assertTrue(result is PositionEvaluation.TriggerClose)
        assertEquals(110.0, (result as PositionEvaluation.TriggerClose).exitPrice, 0.0001)
    }

    @Test fun buyStopGapDownOnCandleFillsAtOpen() {
        val result = engine.evaluatePositionOnCandle(
            position(PositionSide.BUY, 95.0),
            candle(open = 90.0, high = 96.0, low = 89.0, close = 94.0)
        )
        assertTrue(result is PositionEvaluation.TriggerClose)
        assertEquals(90.0, (result as PositionEvaluation.TriggerClose).exitPrice, 0.0001)
    }

    @Test fun sellStopGapUpOnCandleFillsAtOpen() {
        val result = engine.evaluatePositionOnCandle(
            position(PositionSide.SELL, 105.0),
            candle(open = 110.0, high = 112.0, low = 104.0, close = 106.0)
        )
        assertTrue(result is PositionEvaluation.TriggerClose)
        assertEquals(110.0, (result as PositionEvaluation.TriggerClose).exitPrice, 0.0001)
    }

    @Test fun sellStopWithoutGapUsesStopLevel() {
        val result = engine.evaluatePositionOnCandle(
            position(PositionSide.SELL, 105.0),
            candle(open = 100.0, high = 106.0, low = 99.0, close = 102.0)
        )
        assertTrue(result is PositionEvaluation.TriggerClose)
        assertEquals(105.0, (result as PositionEvaluation.TriggerClose).exitPrice, 0.0001)
    }

    @Test fun buyTakeProfitRemainsAtTargetDuringPriceJump() {
        val pos = position(PositionSide.BUY, 90.0).copy(takeProfit = 105.0)
        val result = engine.evaluatePositionOnTick(
            pos, Tick(symbol = "BTCUSDT", bid = 110.0, ask = 110.2)
        )
        assertTrue(result is PositionEvaluation.TriggerClose)
        assertEquals(105.0, (result as PositionEvaluation.TriggerClose).exitPrice, 0.0001)
        assertEquals(ExitReason.TAKE_PROFIT, result.exitReason)
    }

    @Test fun buyGapWithBothStopsTouchedPrioritizesStopLoss() {
        val pos = position(PositionSide.BUY, 95.0).copy(takeProfit = 105.0)
        val result = engine.evaluatePositionOnCandle(
            pos, candle(open = 90.0, high = 110.0, low = 88.0, close = 100.0)
        )
        assertTrue(result is PositionEvaluation.TriggerClose)
        assertEquals(90.0, (result as PositionEvaluation.TriggerClose).exitPrice, 0.0001)
        assertEquals(ExitReason.STOP_LOSS, result.exitReason)
    }

    @Test fun candleWithoutGapUsesStopLevel() {
        val result = engine.evaluatePositionOnCandle(
            position(PositionSide.BUY, 95.0),
            candle(open = 100.0, high = 102.0, low = 94.0, close = 96.0)
        )
        assertTrue(result is PositionEvaluation.TriggerClose)
        assertEquals(95.0, (result as PositionEvaluation.TriggerClose).exitPrice, 0.0001)
    }
}
