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

}
