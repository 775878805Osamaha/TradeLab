package com.example.core.replay

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class HistoricalReplayIntegrityTest {
    private fun candle(time: Long) = Candle(
        symbol = "XAUUSD",
        timeframe = Timeframe.M15,
        openTime = time,
        closeTime = time + 900_000L,
        open = 2010.0,
        high = 2020.0,
        low = 2000.0,
        close = 2015.0,
        volume = 0.0,
        source = "HISTORICAL"
    )

    @Test fun buyStopGapFillsAtAdverseOpenNotRequestedStop() {
        val engine = HistoricalReplayEngine()
        val pos = com.example.core.model.Position(
            accountId = 1, symbol = "XAUUSD",
            side = com.example.core.model.PositionSide.BUY,
            volume = 0.01, entryPrice = 2010.0, currentPrice = 2010.0,
            stopLoss = 2005.0, takeProfit = 2020.0,
            openTime = 0L, profitLoss = 0.0, swap = 0.0,
            commission = 0.0, margin = 100.0
        )
        val gap = candle(900_000L).copy(open = 2000.0, low = 1995.0, high = 2025.0)
        val result = engine.evaluatePositionConservative(pos, gap)
        org.junit.Assert.assertTrue(result is com.example.core.execution.PositionEvaluation.TriggerClose)
        assertEquals(2000.0, (result as com.example.core.execution.PositionEvaluation.TriggerClose).exitPrice, 0.0)
    }

    @Test fun buyTakeProfitGapFillsAtFavorableOpen() {
        val engine = HistoricalReplayEngine()
        val pos = com.example.core.model.Position(
            accountId = 1, symbol = "XAUUSD",
            side = com.example.core.model.PositionSide.BUY,
            volume = 0.01, entryPrice = 2010.0, currentPrice = 2010.0,
            stopLoss = 2005.0, takeProfit = 2020.0,
            openTime = 0L, profitLoss = 0.0, swap = 0.0,
            commission = 0.0, margin = 100.0
        )
        val gap = candle(900_000L).copy(open = 2025.0, low = 2015.0, high = 2030.0)
        val result = engine.evaluatePositionConservative(pos, gap)
        org.junit.Assert.assertTrue(result is com.example.core.execution.PositionEvaluation.TriggerClose)
        assertEquals(2025.0, (result as com.example.core.execution.PositionEvaluation.TriggerClose).exitPrice, 0.0)
    }

    private fun position(
        side: com.example.core.model.PositionSide,
        sl: Double? = null,
        tp: Double? = null
    ) = com.example.core.model.Position(
        accountId = 1, symbol = "XAUUSD", side = side,
        volume = 0.01, entryPrice = 2010.0, currentPrice = 2010.0,
        stopLoss = sl, takeProfit = tp, openTime = 0L,
        profitLoss = 0.0, swap = 0.0, commission = 0.0, margin = 100.0
    )

    private fun assertClose(
        result: com.example.core.execution.PositionEvaluation,
        price: Double,
        reason: com.example.core.model.ExitReason
    ) {
        org.junit.Assert.assertTrue(result is com.example.core.execution.PositionEvaluation.TriggerClose)
        val close = result as com.example.core.execution.PositionEvaluation.TriggerClose
        assertEquals(price, close.exitPrice, 0.0)
        assertEquals(reason, close.exitReason)
    }

    @Test fun sellStopLossGapUsesAdverseOpeningPrice() {
        val bar = candle(900_000L).copy(open = 2025.0, high = 2030.0, low = 2010.0)
        assertClose(
            HistoricalReplayEngine().evaluatePositionConservative(
                position(com.example.core.model.PositionSide.SELL, sl = 2020.0), bar
            ), 2025.0, com.example.core.model.ExitReason.STOP_LOSS
        )
    }

    @Test fun sellTakeProfitGapUsesFavorableOpeningPrice() {
        val bar = candle(900_000L).copy(open = 1995.0, high = 2010.0, low = 1990.0, close = 2000.0)
        assertClose(
            HistoricalReplayEngine().evaluatePositionConservative(
                position(com.example.core.model.PositionSide.SELL, tp = 2000.0), bar
            ), 1995.0, com.example.core.model.ExitReason.TAKE_PROFIT
        )
    }

    @Test fun bothStopsTouchedWithoutOpeningGapChooseStopLoss() {
        val bar = candle(900_000L).copy(open = 2010.0, low = 2000.0, high = 2025.0)
        assertClose(
            HistoricalReplayEngine().evaluatePositionConservative(
                position(com.example.core.model.PositionSide.BUY, sl = 2005.0, tp = 2020.0), bar
            ), 2005.0, com.example.core.model.ExitReason.STOP_LOSS
        )
    }

    @Test fun exactStopTouchFillsAtStopPrice() {
        val bar = candle(900_000L).copy(open = 2010.0, low = 2005.0, high = 2018.0)
        assertClose(
            HistoricalReplayEngine().evaluatePositionConservative(
                position(com.example.core.model.PositionSide.BUY, sl = 2005.0, tp = 2020.0), bar
            ), 2005.0, com.example.core.model.ExitReason.STOP_LOSS
        )
    }

    @Test fun favorableGapDoesNotOverrideStopCollision() {
        val bar = candle(900_000L).copy(open = 2025.0, high = 2030.0, low = 2000.0)
        assertClose(
            HistoricalReplayEngine().evaluatePositionConservative(
                position(com.example.core.model.PositionSide.BUY, sl = 2005.0, tp = 2020.0), bar
            ), 2005.0, com.example.core.model.ExitReason.STOP_LOSS
        )
    }

    @Test fun playAtFinalCandleCannotStartPlayback() {
        val engine = HistoricalReplayEngine()
        engine.initialize(listOf(candle(900_000L), candle(1_800_000L)), startIndex = 1)
        engine.play()
        org.junit.Assert.assertFalse(engine.isPlaying.value)
        assertEquals(ReplayStatus.COMPLETED, engine.status.value)
        assertEquals(1, engine.currentIndex.value)
    }

    @Test fun advanceBarsProcessesEachCandleWithoutSkipping() {
        val engine = HistoricalReplayEngine()
        val bars = (0..10).map { candle(900_000L + it * 900_000L) }
        engine.initialize(bars, startIndex = 0)
        val seen = mutableListOf<Long>()
        engine.onCandleRevealed = { bar, _, _ -> seen.add(bar.openTime) }
        assertEquals(5, engine.advanceBars(5))
        assertEquals(bars.subList(1, 6).map { it.openTime }, seen)
        assertEquals(5, engine.currentIndex.value)
        engine.pause()
    }

    @Test fun enginePreservesValidHistoricalBarCountAndOrdering() {
        val engine = HistoricalReplayEngine()
        val candles = listOf(candle(900_000L), candle(1_800_000L), candle(3_600_000L))
        engine.initialize(candles, startIndex = 0)
        assertEquals(3, engine.totalCandles.value)
        assertEquals(900_000L, engine.currentCandle.value?.openTime)
        engine.pause()
    }

    @Test fun replayQuoteIsTimestampedAtBarCloseNotAtBarOpen() {
        val engine = HistoricalReplayEngine()
        engine.initialize(listOf(candle(900_000L), candle(1_800_000L)), startIndex = 0)
        assertEquals(1_800_000L, engine.currentTick.value?.timestamp)
        assertEquals(1_800_000L, engine.currentReplayTime.value)
        engine.pause()
    }

    @Test fun rejectedReplacementPreservesCurrentReplayDataset() {
        val engine = HistoricalReplayEngine()
        engine.initialize(listOf(candle(900_000L), candle(1_800_000L)), startIndex = 0)
        assertThrows(IllegalArgumentException::class.java) {
            engine.initialize(listOf(candle(900_000L), candle(900_000L)))
        }
        assertEquals(2, engine.totalCandles.value)
        assertEquals(900_000L, engine.currentCandle.value?.openTime)
        engine.pause()
    }

    @Test fun engineRejectsDuplicatesRatherThanSilentlyDroppingTrades() {
        val engine = HistoricalReplayEngine()
        assertThrows(IllegalArgumentException::class.java) {
            engine.initialize(listOf(candle(900_000L), candle(900_000L)))
        }
    }

    @Test fun engineRejectsOutOfOrderHistoryRatherThanSortingIt() {
        val engine = HistoricalReplayEngine()
        assertThrows(IllegalArgumentException::class.java) {
            engine.initialize(listOf(candle(1_800_000L), candle(900_000L)))
        }
    }
}
