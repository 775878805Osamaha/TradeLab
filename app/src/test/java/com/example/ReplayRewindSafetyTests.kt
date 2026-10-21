package com.example

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.core.replay.HistoricalReplayEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.*
import org.junit.Test

class ReplayRewindSafetyTests {
    private fun candle(index: Int) = Candle(
        symbol = "BTCUSDT", timeframe = Timeframe.M15,
        openTime = 1_700_000_000_000L + index * 900_000L,
        open = 100.0 + index, high = 102.0 + index,
        low = 99.0 + index, close = 101.0 + index
    )

    @Test fun steppingBackwardDoesNotReexecuteOrdersOrStrategies() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        var evaluations = 0
        engine.onCandleRevealed = { _, _, _ -> evaluations++ }
        engine.initialize((0..9).map(::candle), startIndex = 3)
        val afterInit = evaluations
        assertTrue(engine.stepForward())
        assertEquals(afterInit + 1, evaluations)
        assertTrue(engine.stepBackward())
        assertEquals(3, engine.currentIndex.value)
        assertEquals(afterInit + 1, evaluations)
        assertEquals(candle(3).openTime, engine.currentCandle.value?.openTime)
        assertTrue(engine.stepForward())
        assertEquals(afterInit + 2, evaluations)
    }

    @Test fun repeatedBackwardStepsNeverInvokeTradingCallback() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        var evaluations = 0
        engine.onCandleRevealed = { _, _, _ -> evaluations++ }
        engine.initialize((0..9).map(::candle), startIndex = 5)
        val before = evaluations
        repeat(3) { assertTrue(engine.stepBackward()) }
        assertEquals(before, evaluations)
        assertEquals(2, engine.currentIndex.value)
    }
    @Test fun seekingToIndexDoesNotEvaluateSkippedOrDestinationCandles() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        var evaluations = 0
        engine.onCandleRevealed = { _, _, _ -> evaluations++ }
        engine.initialize((0..9).map(::candle), startIndex = 2)
        val baseline = evaluations
        engine.jumpToIndex(8)
        assertEquals(8, engine.currentIndex.value)
        assertEquals(baseline, evaluations)
        assertEquals(candle(8).openTime, engine.currentCandle.value?.openTime)
        assertTrue(engine.stepForward())
        assertEquals(baseline + 1, evaluations)
    }

    @Test fun seekingToTimestampDoesNotFireStrategyCallback() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        var evaluations = 0
        engine.onCandleRevealed = { _, _, _ -> evaluations++ }
        engine.initialize((0..9).map(::candle), startIndex = 2)
        val baseline = evaluations
        engine.jumpToTimestamp(candle(6).openTime)
        assertEquals(6, engine.currentIndex.value)
        assertEquals(baseline, evaluations)
    }

    @Test fun initializeAndResetNeverExecuteStrategyOrders() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        var evaluations = 0
        engine.onCandleRevealed = { _, _, _ -> evaluations++ }
        engine.initialize((0..9).map(::candle), startIndex = 4)
        assertEquals(0, evaluations)
        assertEquals(4, engine.currentIndex.value)
        assertTrue(engine.stepForward())
        assertEquals(1, evaluations)
        engine.reset()
        assertEquals(9, engine.currentIndex.value)
        assertEquals(1, evaluations)
        engine.initialize((0..9).map(::candle), startIndex = 2)
        assertEquals(1, evaluations)
        assertTrue(engine.stepForward())
        assertEquals(2, evaluations)
    }

    @Test fun clearInvalidatesOldQuotesCandlesAndTradeCallbacks() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        var evaluations = 0
        engine.onCandleRevealed = { _, _, _ -> evaluations++ }
        engine.initialize((0..9).map(::candle), startIndex = 4)
        assertNotNull(engine.currentTick.value)
        engine.clear()
        assertNull(engine.currentTick.value)
        assertNull(engine.currentCandle.value)
        assertTrue(engine.visibleCandles.value.isEmpty())
        assertEquals(0, engine.totalCandles.value)
        assertEquals(0, engine.currentIndex.value)
        assertFalse(engine.stepForward())
        assertEquals(0, evaluations)
        engine.initialize((0..9).map(::candle), startIndex = 2)
        assertEquals(2, engine.currentIndex.value)
        assertNotNull(engine.currentTick.value)
        assertEquals(0, evaluations)
    }

    @Test fun discardedFutureCheckpointsCannotBeRestored() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        engine.initialize((0..9).map(::candle), startIndex = 3)
        val old = com.example.core.model.ReplayCheckpoint(
            sessionId = 1, candleIndex = 5, timestamp = candle(5).openTime,
            balance = 950.0, equity = 950.0, openPositions = emptyList(),
            closedTradesCount = 1
        )
        engine.recordCheckpoint(old)
        assertNotNull(engine.getCheckpoint(5))
        engine.discardCheckpointsAfter(3)
        assertNull(engine.getCheckpoint(5))
    }

    @Test fun seekingDiscardsStaleFinancialCheckpointsWithoutExecutingTrades() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        var executions = 0
        engine.onCandleRevealed = { _, _, _ -> executions++ }
        engine.initialize((0..9).map(::candle), startIndex = 3)
        engine.recordCheckpoint(com.example.core.model.ReplayCheckpoint(
            sessionId = 1L, candleIndex = 3, timestamp = candle(3).openTime,
            balance = 900.0, equity = 900.0,
            openPositions = emptyList(), closedTradesCount = 1
        ))
        assertNotNull(engine.getCheckpoint(3))
        engine.jumpToIndex(7)
        assertEquals(7, engine.currentIndex.value)
        assertNull(engine.getCheckpoint(3))
        assertEquals(0, executions)
        assertTrue(engine.stepForward())
        assertEquals(1, executions)
    }

    @Test fun replayStopLossClosesExactlyOnceAndRewindDoesNotDuplicateSettlement() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        val position = com.example.core.model.Position(
            id = 1L, accountId = 1L, symbol = "BTCUSDT",
            side = com.example.core.model.PositionSide.BUY, volume = 0.01,
            entryPrice = 104.0, currentPrice = 104.0,
            stopLoss = 104.0, takeProfit = 110.0
        )
        var open = true
        var settlements = 0
        var callbacks = 0
        engine.onCandleRevealed = { bar, _, _ ->
            callbacks++
            if (open) {
                val outcome = engine.evaluatePositionConservative(position, bar)
                if (outcome is com.example.core.execution.PositionEvaluation.TriggerClose) {
                    assertEquals(com.example.core.model.ExitReason.STOP_LOSS, outcome.exitReason)
                    assertEquals(104.0, outcome.exitPrice, 0.0001)
                    settlements++
                    open = false
                }
            }
        }
        engine.initialize((0..9).map(::candle), startIndex = 3)
        assertEquals(0, callbacks)
        assertTrue(engine.stepForward())
        assertEquals(1, settlements)
        assertEquals(1, callbacks)
        assertTrue(engine.stepForward())
        assertEquals(1, settlements)
        assertEquals(2, callbacks)
        assertTrue(engine.stepBackward())
        assertEquals(1, settlements)
        assertEquals(2, callbacks)
        assertTrue(engine.stepForward())
        assertEquals(1, settlements)
        assertEquals(3, callbacks)
    }

    @Test fun conservativeReplayChoosesStopLossWhenStopAndTargetHitSameCandle() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        val position = com.example.core.model.Position(
            id = 1L, accountId = 1L, symbol = "BTCUSDT",
            side = com.example.core.model.PositionSide.BUY, volume = 0.01,
            entryPrice = 104.0, currentPrice = 104.0,
            stopLoss = 104.0, takeProfit = 106.0
        )
        val bar = candle(5)
        assertTrue(bar.low <= 104.0 && bar.high >= 106.0)
        val outcome = engine.evaluatePositionConservative(position, bar)
        assertTrue(outcome is com.example.core.execution.PositionEvaluation.TriggerClose)
        val close = outcome as com.example.core.execution.PositionEvaluation.TriggerClose
        assertEquals(com.example.core.model.ExitReason.STOP_LOSS, close.exitReason)
        assertEquals(104.0, close.exitPrice, 0.0001)
    }

    @Test fun replayRejectsCrossSymbolPositionRiskEvaluation() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        val position = com.example.core.model.Position(
            id = 1L, accountId = 1L, symbol = "ETHUSDT",
            side = com.example.core.model.PositionSide.BUY,
            volume = 0.01, entryPrice = 100.0, currentPrice = 100.0,
            stopLoss = 99.0, takeProfit = 105.0
        )
        assertThrows(IllegalArgumentException::class.java) {
            engine.evaluatePositionConservative(position, candle(4))
        }
    }

    @Test fun replayRejectsNonFiniteRiskInputs() {
        val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
        val position = com.example.core.model.Position(
            id = 1L, accountId = 1L, symbol = "BTCUSDT",
            side = com.example.core.model.PositionSide.BUY,
            volume = Double.NaN, entryPrice = 100.0, currentPrice = 100.0
        )
        assertThrows(IllegalArgumentException::class.java) {
            engine.evaluatePositionConservative(position, candle(4))
        }
    }

}
