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
        assertEquals("COMPLETED", engine.status.value.name)
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

    @Test fun clearResetsHistoricalClockAndMarketQuote() {
        val engine = HistoricalReplayEngine()
        engine.initialize(listOf(candle(900_000L), candle(1_800_000L)), startIndex = 0)
        engine.stepForward()
        engine.clear()
        assertEquals(0L, engine.currentReplayTime.value)
        assertEquals(0L, engine.replayClock.elapsedReplayTime.value)
        assertEquals(null, engine.currentTick.value)
        assertEquals(0, engine.totalCandles.value)
    }

    @Test fun restartResetsElapsedHistoricalTime() {
        val engine = HistoricalReplayEngine()
        val bars = (0..15).map { candle(900_000L + it * 900_000L) }
        engine.initialize(bars, startIndex = 0)
        engine.advanceBars(12)
        org.junit.Assert.assertTrue(engine.replayClock.elapsedReplayTime.value > 0L)
        engine.reset()
        assertEquals(bars[10].closeTime, engine.currentReplayTime.value)
        assertEquals(0L, engine.replayClock.elapsedReplayTime.value)
    }

    @Test fun seekResetsElapsedClockAndNeverExecutesSkippedBars() {
        val engine = HistoricalReplayEngine()
        val bars = (0..20).map { candle(900_000L + it * 900_000L) }
        engine.initialize(bars, startIndex = 0)
        engine.advanceBars(8)
        val events = mutableListOf<Long>()
        engine.onCandleRevealed = { bar, _, _ -> events.add(bar.openTime) }
        engine.jumpToIndex(15)
        assertEquals(15, engine.currentIndex.value)
        assertEquals(bars[15].closeTime, engine.currentReplayTime.value)
        assertEquals(0L, engine.replayClock.elapsedReplayTime.value)
        assertEquals(0, events.size)
        engine.stepForward()
        assertEquals(listOf(bars[16].openTime), events)
    }

    private fun pending(
        type: com.example.core.model.OrderType,
        side: com.example.core.model.OrderSide,
        price: Double
    ) = com.example.core.model.Order(
        id = 1L, accountId = 9999, symbol = "XAUUSD",
        direction = side, type = type, volume = 0.01,
        requestedPrice = price, createdAt = 0L
    )

    @Test fun historicalBuyLimitTouchedIntrabarFillsAtLimit() {
        val bar = candle(900_000L).copy(open = 2010.0, low = 2000.0, high = 2020.0)
        assertEquals(2005.0, HistoricalReplayEngine().pendingOrderFillPrice(
            pending(com.example.core.model.OrderType.BUY_LIMIT, com.example.core.model.OrderSide.BUY, 2005.0), bar
        )!!, 0.0)
    }

    @Test fun historicalBuyStopOpeningGapFillsAtWorseOpen() {
        val bar = candle(900_000L).copy(open = 2015.0, low = 2005.0, high = 2020.0)
        assertEquals(2015.0, HistoricalReplayEngine().pendingOrderFillPrice(
            pending(com.example.core.model.OrderType.BUY_STOP, com.example.core.model.OrderSide.BUY, 2012.0), bar
        )!!, 0.0)
    }

    @Test fun historicalSellStopOpeningGapFillsAtWorseOpen() {
        val bar = candle(900_000L).copy(open = 2000.0, low = 1995.0, high = 2020.0)
        assertEquals(2000.0, HistoricalReplayEngine().pendingOrderFillPrice(
            pending(com.example.core.model.OrderType.SELL_STOP, com.example.core.model.OrderSide.SELL, 2005.0), bar
        )!!, 0.0)
    }

    @Test fun historicalLimitGapUsesBetterOpeningPrice() {
        val bar = candle(900_000L).copy(open = 2000.0, low = 1995.0, high = 2020.0)
        assertEquals(2000.0, HistoricalReplayEngine().pendingOrderFillPrice(
            pending(com.example.core.model.OrderType.BUY_LIMIT, com.example.core.model.OrderSide.BUY, 2005.0), bar
        )!!, 0.0)
    }

    @Test fun historicalUntouchedOrderIsNotFilled() {
        val bar = candle(900_000L)
        assertEquals(null, HistoricalReplayEngine().pendingOrderFillPrice(
            pending(com.example.core.model.OrderType.BUY_LIMIT, com.example.core.model.OrderSide.BUY, 1990.0), bar
        ))
    }

    @Test fun pendingOrdersTriggerOnWicksEvenWhenCloseIsAway() {
        val engine = HistoricalReplayEngine()
        val bar = candle(900_000L)
        val cases = listOf(
            Triple(com.example.core.model.OrderType.BUY_LIMIT, com.example.core.model.OrderSide.BUY, 2005.0),
            Triple(com.example.core.model.OrderType.SELL_LIMIT, com.example.core.model.OrderSide.SELL, 2018.0),
            Triple(com.example.core.model.OrderType.BUY_STOP, com.example.core.model.OrderSide.BUY, 2018.0),
            Triple(com.example.core.model.OrderType.SELL_STOP, com.example.core.model.OrderSide.SELL, 2005.0)
        )
        for ((type, side, price) in cases) {
            val order = pending(type, side, price)
            org.junit.Assert.assertTrue("Expected wick trigger for $type", engine.isPendingOrderTriggeredByCandle(order, bar))
            assertEquals(price, engine.pendingOrderFillPrice(order, bar)!!, 0.0)
        }
    }

    @Test fun pendingOrderGapPricingRespectsLimitAndStopSemantics() {
        val engine = HistoricalReplayEngine()
        val upGap = candle(900_000L).copy(open = 2025.0, high = 2030.0, low = 2020.0, close = 2022.0)
        val downGap = candle(900_000L).copy(open = 1995.0, high = 2000.0, low = 1990.0, close = 1998.0)
        assertEquals(2025.0, engine.pendingOrderFillPrice(pending(com.example.core.model.OrderType.BUY_STOP, com.example.core.model.OrderSide.BUY, 2020.0), upGap)!!, 0.0)
        assertEquals(2025.0, engine.pendingOrderFillPrice(pending(com.example.core.model.OrderType.SELL_LIMIT, com.example.core.model.OrderSide.SELL, 2020.0), upGap)!!, 0.0)
        assertEquals(1995.0, engine.pendingOrderFillPrice(pending(com.example.core.model.OrderType.SELL_STOP, com.example.core.model.OrderSide.SELL, 2000.0), downGap)!!, 0.0)
        assertEquals(1995.0, engine.pendingOrderFillPrice(pending(com.example.core.model.OrderType.BUY_LIMIT, com.example.core.model.OrderSide.BUY, 2000.0), downGap)!!, 0.0)
    }

    @Test fun pendingOrdersOutsideCandleRangeNeverFill() {
        val engine = HistoricalReplayEngine()
        val bar = candle(900_000L)
        val cases = listOf(
            pending(com.example.core.model.OrderType.BUY_LIMIT, com.example.core.model.OrderSide.BUY, 1990.0),
            pending(com.example.core.model.OrderType.SELL_LIMIT, com.example.core.model.OrderSide.SELL, 2030.0),
            pending(com.example.core.model.OrderType.BUY_STOP, com.example.core.model.OrderSide.BUY, 2030.0),
            pending(com.example.core.model.OrderType.SELL_STOP, com.example.core.model.OrderSide.SELL, 1990.0)
        )
        for (order in cases) {
            org.junit.Assert.assertFalse(engine.isPendingOrderTriggeredByCandle(order, bar))
            assertEquals(null, engine.pendingOrderFillPrice(order, bar))
        }
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
