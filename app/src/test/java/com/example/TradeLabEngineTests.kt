package com.example

import com.example.core.backtest.BacktestConfig
import com.example.core.backtest.BacktestEngine
import com.example.core.execution.ExecutionConfig
import com.example.core.execution.ExecutionEngine
import com.example.core.execution.PositionEvaluation
import com.example.core.indicators.TechnicalIndicators
import com.example.core.model.*
import com.example.core.replay.HistoricalReplayEngine
import com.example.core.risk.RiskEngine
import com.example.core.statistics.StatisticsCalculator
import com.example.core.strategy.Signal
import com.example.core.strategy.SignalAction
import com.example.core.strategy.Strategy
import com.example.core.strategy.StrategyContext
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class TradeLabEngineTests {

    private val executionEngine = ExecutionEngine(ExecutionConfig(slippagePips = 0.0, defaultCommissionPerLot = 0.0))
    private val riskEngine = RiskEngine()

    @Test
    fun `test BUY position profit loss calculation`() {
        val account = VirtualAccount(id = 1, name = "Test", balance = 50.0, equity = 50.0)
        val tick = Tick(symbol = "XAUUSD", bid = 2650.00, ask = 2650.25)

        val result = executionEngine.executeMarketOrder(
            account = account,
            symbol = "XAUUSD",
            side = OrderSide.BUY,
            volume = 0.01,
            tick = tick,
            stopLoss = 2640.0,
            takeProfit = 2670.0
        )

        assertTrue(result is com.example.core.execution.ExecutionResult.Success)
        val pos = (result as com.example.core.execution.ExecutionResult.Success).position

        // Entry should be at Ask = 2650.25
        assertEquals(2650.25, pos.entryPrice, 0.001)

        // Evaluate at higher price: Bid = 2660.25 -> Gain = (2660.25 - 2650.25) * 0.01 * 100 = $10.00
        val evalTick = Tick(symbol = "XAUUSD", bid = 2660.25, ask = 2660.50)
        val eval = executionEngine.evaluatePositionOnTick(pos, evalTick)

        assertTrue(eval is PositionEvaluation.KeepOpen)
        val updatedPos = (eval as PositionEvaluation.KeepOpen).updatedPosition
        assertEquals(10.00, updatedPos.profitLoss, 0.001)
    }

    @Test
    fun `test SELL position profit loss calculation`() {
        val account = VirtualAccount(id = 1, name = "Test", balance = 50.0, equity = 50.0)
        val tick = Tick(symbol = "XAUUSD", bid = 2650.00, ask = 2650.25)

        val result = executionEngine.executeMarketOrder(
            account = account,
            symbol = "XAUUSD",
            side = OrderSide.SELL,
            volume = 0.01,
            tick = tick,
            stopLoss = 2660.0,
            takeProfit = 2630.0
        )

        assertTrue(result is com.example.core.execution.ExecutionResult.Success)
        val pos = (result as com.example.core.execution.ExecutionResult.Success).position

        // Entry should be at Bid = 2650.00
        assertEquals(2650.00, pos.entryPrice, 0.001)

        // Evaluate at lower price: Ask = 2640.00 -> Gain = (2650.00 - 2640.00) * 0.01 * 100 = $10.00
        val evalTick = Tick(symbol = "XAUUSD", bid = 2639.75, ask = 2640.00)
        val eval = executionEngine.evaluatePositionOnTick(pos, evalTick)

        assertTrue(eval is PositionEvaluation.KeepOpen)
        val updatedPos = (eval as PositionEvaluation.KeepOpen).updatedPosition
        assertEquals(10.00, updatedPos.profitLoss, 0.001)
    }

    @Test
    fun `test Stop Loss trigger on candle`() {
        val pos = Position(
            id = 1,
            accountId = 1,
            symbol = "XAUUSD",
            side = PositionSide.BUY,
            volume = 0.01,
            entryPrice = 2650.0,
            currentPrice = 2650.0,
            stopLoss = 2645.0,
            takeProfit = 2660.0
        )

        val candle = Candle(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            openTime = 1000L,
            open = 2648.0,
            high = 2652.0,
            low = 2644.0, // breached SL 2645.0
            close = 2646.0
        )

        val eval = executionEngine.evaluatePositionOnCandle(pos, candle)
        assertTrue(eval is PositionEvaluation.TriggerClose)
        val trigger = eval as PositionEvaluation.TriggerClose
        assertEquals(ExitReason.STOP_LOSS, trigger.exitReason)
        assertEquals(2645.0, trigger.exitPrice, 0.001)
    }

    @Test
    fun `test Margin and Risk calculations`() {
        // EURUSD 0.01 lot at price 1.0800 with 100:1 leverage
        // Margin = (0.01 * 100,000 * 1.08) / 100 = $10.80
        val margin = riskEngine.calculateMargin("EURUSD", 0.01, 1.0800, 100.0)
        assertEquals(10.80, margin, 0.01)

        val account = VirtualAccount(
            id = 1,
            name = "Test",
            balance = 50.0,
            equity = 50.0,
            margin = 0.0,
            freeMargin = 50.0,
            leverage = 100.0
        )

        val analysis = riskEngine.analyzeRisk(
            account = account,
            symbol = "EURUSD",
            side = OrderSide.BUY,
            volume = 0.01,
            entryPrice = 1.0800,
            stopLoss = 1.0750,
            takeProfit = 1.0900
        )

        assertTrue(analysis.isMarginSufficient)
        assertEquals(10.80, analysis.requiredMargin, 0.01)
        assertEquals(39.20, analysis.freeMarginRemaining, 0.01)
        assertTrue(analysis.potentialLoss > 0)
        assertTrue(analysis.potentialProfit > 0)
        assertEquals(2.0, analysis.riskRewardRatio ?: 0.0, 0.01)
    }

    @Test
    fun `test StatisticsCalculator calculations`() {
        val trades = listOf(
            TradeJournalEntry(
                id = 1,
                accountId = 1,
                symbol = "EURUSD",
                side = PositionSide.BUY,
                volume = 0.01,
                entryPrice = 1.0800,
                exitPrice = 1.0850,
                profitLoss = 5.0,
                openTime = 1000L,
                closeTime = 2000L,
                exitReason = ExitReason.TAKE_PROFIT,
                rMultiple = 2.0
            ),
            TradeJournalEntry(
                id = 2,
                accountId = 1,
                symbol = "EURUSD",
                side = PositionSide.BUY,
                volume = 0.01,
                entryPrice = 1.0800,
                exitPrice = 1.0780,
                profitLoss = -2.0,
                openTime = 3000L,
                closeTime = 4000L,
                exitReason = ExitReason.STOP_LOSS,
                rMultiple = -1.0
            )
        )

        val metrics = StatisticsCalculator.calculate(initialBalance = 50.0, trades = trades)

        assertEquals(2, metrics.totalTrades)
        assertEquals(1, metrics.winningTrades)
        assertEquals(1, metrics.losingTrades)
        assertEquals(50.0, metrics.winRatePct, 0.01)
        assertEquals(3.0, metrics.netProfit, 0.01)
        assertEquals(53.0, metrics.finalBalance, 0.01)
        assertEquals(2.5, metrics.profitFactor ?: 0.0, 0.01) // 5.0 / 2.0 = 2.5
    }

    @Test
    fun `test Replay lookahead bias protection`() {
        val replayEngine = HistoricalReplayEngine()
        val dummyCandles = (0..50).map { i ->
            Candle(
                symbol = "XAUUSD",
                timeframe = Timeframe.M15,
                openTime = 1000L + (i * 60000L),
                open = 2650.0 + i,
                high = 2652.0 + i,
                low = 2649.0 + i,
                close = 2651.0 + i,
                volume = 100.0
            )
        }

        replayEngine.initialize(dummyCandles, startIndex = 10)

        // Only 11 candles (0 to 10) must be visible, never candles 11 to 50!
        assertEquals(11, replayEngine.visibleCandles.value.size)
        assertEquals(dummyCandles[10].openTime, replayEngine.currentCandle.value?.openTime)

        // Step forward
        replayEngine.stepForward()
        assertEquals(12, replayEngine.visibleCandles.value.size)
        assertEquals(dummyCandles[11].openTime, replayEngine.currentCandle.value?.openTime)
    }

    @Test
    fun `test BacktestEngine runs without future lookahead`() = runBlocking {
        val backtestEngine = BacktestEngine()
        val dummyCandles = (0..60).map { i ->
            Candle(
                symbol = "XAUUSD",
                timeframe = Timeframe.M15,
                openTime = 1000L + (i * 60000L),
                open = 2650.0 + (if (i % 2 == 0) 5.0 else -5.0),
                high = 2660.0,
                low = 2640.0,
                close = 2650.0 + (if (i % 2 == 0) -5.0 else 5.0),
                volume = 100.0
            )
        }

        val dummyStrategy = object : Strategy {
            override val id: String = "DUMMY_TEST"
            override val name: String = "Dummy Test Strategy"
            override val description: String = "Test-only strategy"
            override val defaultParameters: Map<String, Any> = emptyMap()
            override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal = Signal(action = SignalAction.HOLD)
        }

        val config = BacktestConfig(
            strategy = dummyStrategy,
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            initialBalance = 50.0,
            fixedLotSize = 0.01
        )

        val result = backtestEngine.runBacktest(dummyCandles, config)

        assertNotNull(result)
        assertEquals(61, result.totalCandlesProcessed)
        assertTrue(result.equityCurve.isNotEmpty())
    }

    @Test
    fun `test DataIntegrityValidator rejects invalid OHLC candles`() {
        val validCandle = Candle(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            openTime = 1000L,
            closeTime = 2000L,
            open = 2650.0,
            high = 2655.0,
            low = 2645.0,
            close = 2652.0
        )
        assertTrue(com.example.core.market.DataIntegrityValidator.validateCandle(validCandle).isValid)

        // Invalid 1: High < Open
        val badHigh = validCandle.copy(high = 2640.0)
        assertFalse(com.example.core.market.DataIntegrityValidator.validateCandle(badHigh).isValid)

        // Invalid 2: Low > Close
        val badLow = validCandle.copy(low = 2654.0)
        assertFalse(com.example.core.market.DataIntegrityValidator.validateCandle(badLow).isValid)

        // Invalid 3: openTime >= closeTime
        val badTimestamp = validCandle.copy(openTime = 3000L, closeTime = 2000L)
        assertFalse(com.example.core.market.DataIntegrityValidator.validateCandle(badTimestamp).isValid)
    }

    @Test
    fun `test DataIntegrityValidator sanitizes duplicates and sorts chronologically`() {
        val c1 = Candle(
            symbol = "EURUSD",
            timeframe = Timeframe.H1,
            openTime = 3000L,
            closeTime = 4000L,
            open = 1.0800,
            high = 1.0850,
            low = 1.0790,
            close = 1.0820
        )
        val c2Duplicate = Candle(
            symbol = "EURUSD",
            timeframe = Timeframe.H1,
            openTime = 1000L,
            closeTime = 2000L,
            open = 1.0750,
            high = 1.0780,
            low = 1.0740,
            close = 1.0760
        )
        val c2Original = Candle(
            symbol = "EURUSD",
            timeframe = Timeframe.H1,
            openTime = 1000L,
            closeTime = 2000L,
            open = 1.0750,
            high = 1.0790,
            low = 1.0730,
            close = 1.0770
        )
        val c3 = Candle(
            symbol = "EURUSD",
            timeframe = Timeframe.H1,
            openTime = 2000L,
            closeTime = 3000L,
            open = 1.0770,
            high = 1.0810,
            low = 1.0760,
            close = 1.0800
        )

        // Unordered and containing duplicate at 1000L
        val rawCandles = listOf(c1, c2Duplicate, c3, c2Original)
        val sanitized = com.example.core.market.DataIntegrityValidator.sanitizeCandles(rawCandles)

        // Must be exactly 3 unique candles
        assertEquals(3, sanitized.size)
        // Must be sorted strictly in ascending order: 1000L, 2000L, 3000L
        assertEquals(1000L, sanitized[0].openTime)
        assertEquals(2000L, sanitized[1].openTime)
        assertEquals(3000L, sanitized[2].openTime)
    }

    @Test
    fun `test DataIntegrityValidator enforces replay barrier`() {
        val candles = (1..10).map { i ->
            Candle(
                symbol = "BTCUSDT",
                timeframe = Timeframe.M15,
                openTime = i * 1000L,
                closeTime = (i + 1) * 1000L,
                open = 60000.0,
                high = 60100.0,
                low = 59900.0,
                close = 60050.0
            )
        }

        val barrierTime = 5000L
        val allowedCandles = com.example.core.market.DataIntegrityValidator.enforceReplayBarrier(candles, barrierTime)

        assertEquals(5, allowedCandles.size)
        assertTrue(allowedCandles.all { it.openTime <= barrierTime })
    }

    @Test
    fun `test Crypto symbols use actual provider symbols`() {
        val btc = com.example.core.market.DefaultSymbols.getSymbol("BTCUSD")
        assertEquals("BTCUSDT", btc.symbol)

        val eth = com.example.core.market.DefaultSymbols.getSymbol("ETHUSD")
        assertEquals("ETHUSDT", eth.symbol)
    }

    @Test
    fun `test Pending orders execution for BUY LIMIT and SELL STOP`() {
        val account = VirtualAccount(id = 1, name = "Test", balance = 100.0, freeMargin = 100.0)

        // 1. BUY LIMIT at 2640.0 (triggered when Ask <= 2640.0)
        val buyLimit = Order(
            id = 1,
            accountId = 1,
            symbol = "XAUUSD",
            direction = OrderSide.BUY,
            type = OrderType.BUY_LIMIT,
            volume = 0.01,
            requestedPrice = 2640.0
        )

        // Untriggered tick: Ask = 2645.0
        val tick1 = Tick(symbol = "XAUUSD", bid = 2644.8, ask = 2645.0)
        assertNull(executionEngine.evaluatePendingOrder(buyLimit, tick1, account))

        // Triggered tick: Ask = 2639.5
        val tick2 = Tick(symbol = "XAUUSD", bid = 2639.2, ask = 2639.5)
        val execResult = executionEngine.evaluatePendingOrder(buyLimit, tick2, account)
        assertNotNull(execResult)
        assertTrue(execResult is com.example.core.execution.ExecutionResult.Success)
        val pos = (execResult as com.example.core.execution.ExecutionResult.Success).position
        assertEquals(PositionSide.BUY, pos.side)
        assertEquals(2640.0, pos.entryPrice, 0.001)

        // 2. SELL STOP at 2630.0 (triggered when Bid <= 2630.0)
        val sellStop = Order(
            id = 2,
            accountId = 1,
            symbol = "XAUUSD",
            direction = OrderSide.SELL,
            type = OrderType.SELL_STOP,
            volume = 0.01,
            requestedPrice = 2630.0
        )
        // Untriggered: Bid = 2635.0
        assertNull(executionEngine.evaluatePendingOrder(sellStop, tick2, account))

        // Triggered: Bid = 2629.0
        val tick3 = Tick(symbol = "XAUUSD", bid = 2629.0, ask = 2629.3)
        val execSell = executionEngine.evaluatePendingOrder(sellStop, tick3, account)
        assertNotNull(execSell)
        assertTrue(execSell is com.example.core.execution.ExecutionResult.Success)
    }

    @Test
    fun `test Partial Close position calculation`() {
        val originalPos = Position(
            id = 1,
            accountId = 1,
            symbol = "XAUUSD",
            side = PositionSide.BUY,
            volume = 1.00,
            entryPrice = 2650.0,
            currentPrice = 2660.0,
            commission = 5.0,
            margin = 2650.0
        )

        // Close 0.40 lot at 2660.0 -> Gain = (2660.0 - 2650.0) * 0.40 * 100 = $400.00
        val (trade, remaining) = executionEngine.closePosition(
            position = originalPos,
            exitPrice = 2660.0,
            exitReason = ExitReason.MANUAL_CLOSE,
            partialVolume = 0.40
        )

        assertEquals(0.40, trade.volume, 0.001)
        assertEquals(400.0, trade.profitLoss, 0.001)
        assertEquals(2.0, trade.commission, 0.001) // 5.0 * (0.4 / 1.0) = 2.0

        assertNotNull(remaining)
        assertEquals(0.60, remaining!!.volume, 0.001)
        assertEquals(3.0, remaining.commission, 0.001) // 5.0 - 2.0 = 3.0
    }

    @Test
    fun `test Break-Even calculation prevents moving SL when not in profit`() {
        val buyPos = Position(
            id = 1,
            accountId = 1,
            symbol = "XAUUSD",
            side = PositionSide.BUY,
            volume = 0.01,
            entryPrice = 2650.0,
            currentPrice = 2648.0
        )
        // Tick currently at loss: bid = 2648.0 < entry = 2650.0
        val lossTick = Tick(symbol = "XAUUSD", bid = 2648.0, ask = 2648.3)
        val beLossResult = executionEngine.calculateBreakEven(buyPos, lossTick)
        assertTrue(beLossResult.isFailure)

        // Tick in profit: bid = 2655.0 > entry = 2650.0
        val profitTick = Tick(symbol = "XAUUSD", bid = 2655.0, ask = 2655.3)
        val beProfitResult = executionEngine.calculateBreakEven(buyPos, profitTick, protectionOffsetPips = 2.0)
        assertTrue(beProfitResult.isSuccess)
        val bePrice = beProfitResult.getOrThrow()
        // entry 2650.0 + (2.0 * 0.01) = 2650.02
        assertEquals(2650.02, bePrice, 0.001)
    }

    @Test
    fun `test Trailing Stop requires minimum movement threshold`() {
        val buyPos = Position(
            id = 1,
            accountId = 1,
            symbol = "XAUUSD",
            side = PositionSide.BUY,
            volume = 0.01,
            entryPrice = 2650.0,
            currentPrice = 2660.0,
            stopLoss = 2655.0,
            trailingStopDistance = 5.0 // distance = $5.00
        )

        // Small tick: bid = 2660.00 -> candidate = 2655.00 (same as current SL 2655.0) -> null
        val tickSame = Tick(symbol = "XAUUSD", bid = 2660.00, ask = 2660.25)
        assertNull(executionEngine.calculateTrailingStopUpdate(buyPos, tickSame, minStepPips = 1.0))

        // Price rises: bid = 2663.00 -> candidate = 2658.00 (improves SL from 2655.0 to 2658.0)
        val tickHigher = Tick(symbol = "XAUUSD", bid = 2663.00, ask = 2663.25)
        val newSl = executionEngine.calculateTrailingStopUpdate(buyPos, tickHigher, minStepPips = 1.0)
        assertNotNull(newSl)
        assertEquals(2658.00, newSl!!, 0.001)
    }

    @Test
    fun `test OrderValidator rejects invalid orders`() {
        val account = VirtualAccount(id = 1, name = "Test", balance = 50.0, freeMargin = 50.0)
        val tick = Tick(symbol = "XAUUSD", bid = 2650.0, ask = 2650.25)

        // 1. Insufficient margin: volume = 5.0 lot on $50 account with 100x leverage requires ~$13,250
        val marginReject = com.example.core.execution.OrderValidator.validate(
            account = account,
            symbol = "XAUUSD",
            type = OrderType.MARKET,
            side = OrderSide.BUY,
            volume = 5.0,
            tick = tick
        )
        assertTrue(marginReject is com.example.core.execution.OrderValidationResult.Rejected)
        assertEquals(com.example.core.execution.OrderRejectionReason.INSUFFICIENT_MARGIN, (marginReject as com.example.core.execution.OrderValidationResult.Rejected).reason)

        // 2. Invalid Stop Loss for BUY: SL is above entry price
        val slReject = com.example.core.execution.OrderValidator.validate(
            account = account,
            symbol = "XAUUSD",
            type = OrderType.MARKET,
            side = OrderSide.BUY,
            volume = 0.01,
            tick = tick,
            stopLoss = 2660.0
        )
        assertTrue(slReject is com.example.core.execution.OrderValidationResult.Rejected)
        assertEquals(com.example.core.execution.OrderRejectionReason.INVALID_SL, (slReject as com.example.core.execution.OrderValidationResult.Rejected).reason)

        // 3. Invalid volume (less than minLot 0.01)
        val volReject = com.example.core.execution.OrderValidator.validate(
            account = account,
            symbol = "XAUUSD",
            type = OrderType.MARKET,
            side = OrderSide.BUY,
            volume = 0.001,
            tick = tick
        )
        assertTrue(volReject is com.example.core.execution.OrderValidationResult.Rejected)
        assertEquals(com.example.core.execution.OrderRejectionReason.INVALID_VOLUME, (volReject as com.example.core.execution.OrderValidationResult.Rejected).reason)
    }

    @Test
    fun `test Account safe calculations and zero margin division protection`() {
        // When usedMargin = 0.0, marginLevel must be 0.0 and formatted as N/A (never NaN or Infinity)
        val accZeroMargin = VirtualAccount(
            id = 1,
            name = "Test",
            balance = 50.0,
            equity = 50.0,
            margin = 0.0,
            freeMargin = 50.0
        )
        assertEquals(0.0, accZeroMargin.marginLevel, 0.001)
        assertEquals("N/A", accZeroMargin.marginLevelFormatted)

        // When usedMargin = 25.0 and equity = 50.0 -> marginLevel = (50 / 25) * 100 = 200.0%
        val marginLevel = VirtualAccount.computeMarginLevel(equity = 50.0, usedMargin = 25.0)
        assertEquals(200.0, marginLevel, 0.01)
        val freeMargin = VirtualAccount.computeFreeMargin(equity = 50.0, usedMargin = 25.0)
        assertEquals(25.0, freeMargin, 0.01)
    }

    @Test
    fun `test RiskEngine calculateSuggestedLotFromFixedRiskAmount`() {
        val account = VirtualAccount(id = 1, name = "Test", balance = 50.0)
        // Fixed risk $5.00 on EURUSD with 50 pips SL
        // Loss per lot = 50 pips * 0.0001 * 100,000 = $500 per lot
        // Lot = 5 / 500 = 0.01 lot
        val lot = riskEngine.calculateSuggestedLotFromFixedRiskAmount(
            account = account,
            symbol = "EURUSD",
            fixedRiskAmount = 5.0,
            stopLossPips = 50.0
        )
        assertEquals(0.01, lot, 0.001)
    }

    @Test
    fun `test HistoricalReplayEngine conservative intrabar SL priority over TP`() {
        val replayEngine = com.example.core.replay.HistoricalReplayEngine()
        val pos = Position(
            id = 10,
            accountId = 1,
            symbol = "XAUUSD",
            side = PositionSide.BUY,
            volume = 0.01,
            entryPrice = 2650.0,
            currentPrice = 2650.0,
            stopLoss = 2640.0,
            takeProfit = 2660.0
        )

        // Candle expands past both SL (2640) and TP (2660): Low = 2635, High = 2665
        val volatileCandle = Candle(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            openTime = 10000L,
            closeTime = 20000L,
            open = 2650.0,
            high = 2665.0,
            low = 2635.0,
            close = 2655.0
        )

        val eval = replayEngine.evaluatePositionConservative(pos, volatileCandle)
        assertTrue(eval is com.example.core.execution.PositionEvaluation.TriggerClose)
        val trigger = eval as com.example.core.execution.PositionEvaluation.TriggerClose
        assertEquals(ExitReason.STOP_LOSS, trigger.exitReason)
        assertEquals(2640.0, trigger.exitPrice, 0.001)
    }

    @Test
    fun `test HistoricalReplayEngine checkpoint record and retrieve`() {
        val replayEngine = com.example.core.replay.HistoricalReplayEngine()
        val checkpoint = com.example.core.model.ReplayCheckpoint(
            sessionId = 1,
            candleIndex = 15,
            timestamp = 150000L,
            balance = 55.40,
            equity = 55.40,
            openPositions = emptyList(),
            closedTradesCount = 2
        )
        replayEngine.recordCheckpoint(checkpoint)
        val retrieved = replayEngine.getCheckpoint(15)
        assertNotNull(retrieved)
        assertEquals(55.40, retrieved!!.balance, 0.001)
        assertEquals(2, retrieved.closedTradesCount)
    }
}
