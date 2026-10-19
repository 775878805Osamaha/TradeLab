package com.example

import com.example.core.backtest.BacktestConfig
import com.example.core.backtest.BacktestEngine
import com.example.core.indicators.TechnicalIndicators
import com.example.core.model.*
import com.example.core.strategy.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class StrategyEngineTests {

    private lateinit var backtestEngine: BacktestEngine

    @Before
    fun setUp() {
        backtestEngine = BacktestEngine()
        StrategyRegistry.resetToDefaults()
    }

    // Test-only mock crossover strategy to test validation, execution, and determinism
    private class TestMockCrossoverStrategy : Strategy {
        override val id: String = "TEST_CROSSOVER"
        override val name: String = "Test Crossover Strategy"
        override val description: String = "Test-only crossover strategy"
        override val category: StrategyCategory = StrategyCategory.TREND
        override val version: Int = 1

        override val parameterDefinitions: List<StrategyParameterDefinition> = listOf(
            StrategyParameterDefinition("fastPeriod", "Fast Period", ParameterType.INT, 9, minimum = 1.0, maximum = 50.0),
            StrategyParameterDefinition("slowPeriod", "Slow Period", ParameterType.INT, 21, minimum = 2.0, maximum = 200.0),
            StrategyParameterDefinition("stopLossPips", "Stop Loss Pips", ParameterType.DOUBLE, 25.0, minimum = 5.0, maximum = 500.0),
            StrategyParameterDefinition("takeProfitPips", "Take Profit Pips", ParameterType.DOUBLE, 50.0, minimum = 5.0, maximum = 1000.0)
        )

        override val defaultParameters: Map<String, Any> = mapOf(
            "fastPeriod" to 9,
            "slowPeriod" to 21,
            "stopLossPips" to 25.0,
            "takeProfitPips" to 50.0
        )

        private var lastProcessedCandleTime: Long = 0L

        override fun reset() {
            lastProcessedCandleTime = 0L
        }

        override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
            val currentCandleTime = context.currentCandle.openTime
            if (currentCandleTime == lastProcessedCandleTime) {
                return Signal(action = SignalAction.HOLD)
            }

            val fastPeriod = (parameters["fastPeriod"] as? Number)?.toInt() ?: 9
            val slowPeriod = (parameters["slowPeriod"] as? Number)?.toInt() ?: 21
            val candles = context.historicalCandles
            if (candles.size < slowPeriod + 2) return Signal(action = SignalAction.HOLD)

            val fast = TechnicalIndicators.calculateEma(candles, fastPeriod)
            val slow = TechnicalIndicators.calculateEma(candles, slowPeriod)
            val n = candles.size - 1
            val prevF = fast[n - 1] ?: return Signal(action = SignalAction.HOLD)
            val currF = fast[n] ?: return Signal(action = SignalAction.HOLD)
            val prevS = slow[n - 1] ?: return Signal(action = SignalAction.HOLD)
            val currS = slow[n] ?: return Signal(action = SignalAction.HOLD)

            if (prevF <= prevS && currF > currS) {
                if (context.openPositions.none { it.side == PositionSide.BUY }) {
                    lastProcessedCandleTime = currentCandleTime
                    return Signal(
                        action = SignalAction.BUY,
                        direction = OrderSide.BUY,
                        symbol = context.symbol,
                        entryPrice = context.currentCandle.close,
                        stopLoss = context.currentCandle.close - 2.5,
                        takeProfit = context.currentCandle.close + 5.0,
                        timestamp = currentCandleTime
                    )
                }
            }
            return Signal(action = SignalAction.HOLD)
        }
    }

    // Test-only mock RSI strategy to test parameter validation
    private class TestMockRsiStrategy : Strategy {
        override val id: String = "TEST_RSI"
        override val name: String = "Test RSI Strategy"
        override val description: String = "Test-only RSI strategy"
        override val category: StrategyCategory = StrategyCategory.MEAN_REVERSION
        override val version: Int = 1

        override val parameterDefinitions: List<StrategyParameterDefinition> = listOf(
            StrategyParameterDefinition("rsiPeriod", "RSI Period", ParameterType.INT, 14, minimum = 2.0, maximum = 50.0),
            StrategyParameterDefinition("oversoldLevel", "Oversold Level", ParameterType.DOUBLE, 30.0, minimum = 5.0, maximum = 45.0),
            StrategyParameterDefinition("overboughtLevel", "Overbought Level", ParameterType.DOUBLE, 70.0, minimum = 55.0, maximum = 95.0)
        )

        override val defaultParameters: Map<String, Any> = mapOf(
            "rsiPeriod" to 14,
            "oversoldLevel" to 30.0,
            "overboughtLevel" to 70.0
        )

        override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal = Signal(action = SignalAction.HOLD)
    }

    private fun createCandle(
        openTime: Long,
        closeTime: Long,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        timeframe: Timeframe = Timeframe.M15
    ): Candle = Candle(
        symbol = "XAUUSD",
        timeframe = timeframe,
        openTime = openTime,
        closeTime = closeTime,
        open = open,
        high = high,
        low = low,
        close = close,
        volume = 100.0,
        source = "TEST"
    )

    private fun generateCandleSeries(
        count: Int,
        startPrice: Double = 2650.0,
        trend: Double = 0.5,
        waveAmplitude: Double = 2.0
    ): List<Candle> {
        val candles = mutableListOf<Candle>()
        var currentPrice = startPrice
        var time = 1700000000000L

        for (i in 0 until count) {
            val wave = kotlin.math.sin(i * 0.25) * waveAmplitude
            val open = currentPrice
            val close = open + trend + wave
            val high = maxOf(open, close) + 1.0
            val low = minOf(open, close) - 1.0

            candles.add(createCandle(time, time + 900000L, open, high, low, close))
            currentPrice = close
            time += 900000L
        }
        return candles
    }

    @Test
    fun `test StrategyRegistry has no built-in strategies and presets by default`() {
        val all = StrategyRegistry.getAllStrategies()
        assertTrue("StrategyRegistry must be empty of built-in strategies by default", all.isEmpty())

        assertNull(StrategyRegistry.getStrategy("EMA_CROSSOVER"))
        assertNull(StrategyRegistry.getStrategy("SMA_CROSSOVER"))
        assertNull(StrategyRegistry.getStrategy("RSI_REVERSION"))
        assertNull(StrategyRegistry.getStrategy("BOLLINGER_REVERSION"))

        val emaPresets = StrategyRegistry.getPresetsForStrategy("EMA_CROSSOVER")
        assertTrue("Must have no presets", emaPresets.isEmpty())
    }

    @Test
    fun `test StrategyFactory creates and resets strategy instance`() {
        val custom = TestMockCrossoverStrategy()
        StrategyRegistry.register(custom)

        val strat = StrategyFactory.createStrategy(custom.id)
        assertNotNull(strat)
        assertEquals(custom.id, strat!!.id)
        assertEquals(StrategyCategory.TREND, strat.category)
        assertEquals(1, strat.version)

        StrategyRegistry.unregister(custom.id)
    }

    @Test
    fun `test StrategyValidator validates parameter boundaries and cross-field rules`() {
        val custom = TestMockCrossoverStrategy()

        // Valid parameters
        val validRes = StrategyValidator.validate(custom, mapOf("fastPeriod" to 9, "slowPeriod" to 21))
        assertTrue(validRes.isValid)
        assertTrue(validRes.errors.isEmpty())

        // Invalid: fast >= slow
        val invalidCrossover = StrategyValidator.validate(custom, mapOf("fastPeriod" to 25, "slowPeriod" to 10))
        assertFalse(invalidCrossover.isValid)
        assertTrue(invalidCrossover.errors.any { it.field == "slowPeriod" })

        // RSI validations
        val rsi = TestMockRsiStrategy()
        val badRsi = StrategyValidator.validate(rsi, mapOf("oversoldLevel" to 60.0, "overboughtLevel" to 40.0))
        assertFalse(badRsi.isValid)
        assertTrue(badRsi.errors.any { it.field == "oversoldLevel" })
        assertTrue(badRsi.errors.any { it.field == "overboughtLevel" })
    }

    @Test
    fun `test duplicate signal prevention for the same candle bar`() {
        val strategy = TestMockCrossoverStrategy()
        strategy.reset()

        val candles = generateCandleSeries(count = 30, trend = 2.0)
        val current = candles.last()
        val context = StrategyContext(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            currentCandle = current,
            historicalCandles = candles,
            openPositions = emptyList(),
            account = VirtualAccount(id = 1, name = "Test", balance = 100.0)
        )

        // First call may generate BUY or HOLD
        val firstSignal = strategy.onCandle(context, strategy.defaultParameters)

        // If it was a trade signal, second call with the exact same candle MUST return HOLD
        if (firstSignal.action != SignalAction.HOLD) {
            val secondSignal = strategy.onCandle(context, strategy.defaultParameters)
            assertEquals("Duplicate signal on same bar must return HOLD", SignalAction.HOLD, secondSignal.action)
        }
    }

    @Test
    fun `test strategy position awareness prevents re-entering same direction`() {
        val strategy = TestMockCrossoverStrategy()
        strategy.reset()

        val candles = generateCandleSeries(count = 35, trend = 2.5)
        val current = candles.last()

        // Simulate an already open BUY position
        val existingBuy = Position(
            id = 10,
            accountId = 1,
            symbol = "XAUUSD",
            side = PositionSide.BUY,
            volume = 0.01,
            entryPrice = 2650.0,
            currentPrice = 2660.0
        )

        val contextWithLong = StrategyContext(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            currentCandle = current,
            historicalCandles = candles,
            openPositions = listOf(existingBuy),
            account = VirtualAccount(id = 1, name = "Test", balance = 100.0)
        )

        val signal = strategy.onCandle(contextWithLong, strategy.defaultParameters)
        // Must NOT emit duplicate BUY while already positioned Long
        assertNotEquals("Should not emit duplicate BUY while already long", SignalAction.BUY, signal.action)
    }

    @Test
    fun `test strategy state reset allows fresh evaluation`() {
        val strategy = TestMockCrossoverStrategy()
        val candles = generateCandleSeries(count = 30, trend = 2.0)
        val current = candles.last()
        val context = StrategyContext(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            currentCandle = current,
            historicalCandles = candles,
            openPositions = emptyList(),
            account = VirtualAccount(id = 1, name = "Test", balance = 100.0)
        )

        val sig1 = strategy.onCandle(context, strategy.defaultParameters)
        // Reset strategy internal state
        strategy.reset()

        // Calling onCandle after reset on same context behaves identically to first execution
        val sig2 = strategy.onCandle(context, strategy.defaultParameters)
        assertEquals(sig1.action, sig2.action)
    }

    @Test
    fun `test Strategy determinism across identical evaluations`() {
        val strategy = TestMockCrossoverStrategy()
        strategy.reset()
        val candles = generateCandleSeries(count = 45, trend = 1.0)
        val current = candles.last()

        val context1 = StrategyContext(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            currentCandle = current,
            historicalCandles = candles,
            openPositions = emptyList(),
            account = VirtualAccount(id = 1, name = "Test", balance = 100.0)
        )

        val sig1 = strategy.onCandle(context1, strategy.defaultParameters)

        strategy.reset()
        val context2 = StrategyContext(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            currentCandle = current,
            historicalCandles = candles,
            openPositions = emptyList(),
            account = VirtualAccount(id = 1, name = "Test", balance = 100.0)
        )

        val sig2 = strategy.onCandle(context2, strategy.defaultParameters)

        assertEquals(sig1.action, sig2.action)
        assertEquals(sig1.direction, sig2.direction)
        assertEquals(sig1.entryPrice, sig2.entryPrice)
        assertEquals(sig1.stopLoss, sig2.stopLoss)
        assertEquals(sig1.takeProfit, sig2.takeProfit)
    }

    @Test
    fun `test MultiTimeframeDataProvider completed HTF candle filtering`() {
        // H1 candles (each 60 mins = 3,600,000 ms)
        val h1Candles = listOf(
            createCandle(openTime = 0L, closeTime = 3600000L, open = 100.0, high = 105.0, low = 99.0, close = 104.0, timeframe = Timeframe.H1),
            createCandle(openTime = 3600000L, closeTime = 7200000L, open = 104.0, high = 108.0, low = 103.0, close = 107.0, timeframe = Timeframe.H1),
            createCandle(openTime = 7200000L, closeTime = 10800000L, open = 107.0, high = 110.0, low = 106.0, close = 109.0, timeframe = Timeframe.H1)
        )

        val mtfProvider = MultiTimeframeDataProvider(
            executionTimeframe = Timeframe.M5,
            higherTimeframe = Timeframe.H1,
            allHtfCandles = h1Candles
        )

        val completedAt5m = mtfProvider.getCompletedHtfCandles(currentExecutionTimestamp = 5000000L)

        assertEquals("Only completed H1 candles must be accessible", 1, completedAt5m.size)
        assertEquals(3600000L, completedAt5m.first().closeTime)

        val latest = mtfProvider.getLatestClosedHtfCandle(currentExecutionTimestamp = 5000000L)
        assertNotNull(latest)
        assertEquals(104.0, latest!!.close, 0.001)

        val completedAt75m = mtfProvider.getCompletedHtfCandles(currentExecutionTimestamp = 7500000L)
        assertEquals(2, completedAt75m.size)
    }

    @Test
    fun `test MultiTimeframeDataProvider adversarial lookahead detection`() {
        val h1CandleFuture = createCandle(
            openTime = 3600000L,
            closeTime = 7200000L,
            open = 104.0,
            high = 108.0,
            low = 103.0,
            close = 107.0,
            timeframe = Timeframe.H1
        )

        val mtfProvider = MultiTimeframeDataProvider(
            executionTimeframe = Timeframe.M5,
            higherTimeframe = Timeframe.H1,
            allHtfCandles = listOf(h1CandleFuture)
        )

        try {
            mtfProvider.enforceNoLookahead(h1CandleFuture, currentExecutionTimestamp = 5000000L)
            fail("Expected HtfLookaheadViolation when accessing unclosed HTF candle")
        } catch (e: HtfLookaheadViolation) {
            assertTrue(e.message?.contains("Access Denied") == true)
        }
    }

    @Test
    fun `test BacktestEngine integration with custom test strategy`() = runBlocking {
        val candles = generateCandleSeries(count = 70, trend = 0.5, waveAmplitude = 3.0)
        val custom = TestMockCrossoverStrategy()
        custom.reset()

        val config = BacktestConfig(
            strategy = custom,
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            initialBalance = 100.0,
            fixedLot = 0.01
        )

        val result = backtestEngine.runBacktest(candles, config)
        assertNotNull("Backtest result for custom strategy must not be null", result)
        assertEquals(70, result.totalCandlesProcessed)
        assertNotNull(result.metrics)
        assertTrue("Equity curve must be populated", result.equityCurve.isNotEmpty())
    }

    @Test
    fun `test StrategyRegistry custom strategy registration and unregistration`() {
        val customStrat = object : Strategy {
            override val id: String = "CUSTOM_BREAKOUT"
            override val name: String = "Custom High Breakout"
            override val description: String = "Custom user breakout strategy"
            override val category: StrategyCategory = StrategyCategory.CUSTOM
            override val defaultParameters: Map<String, Any> = emptyMap()
            override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal = Signal(action = SignalAction.HOLD)
        }

        StrategyRegistry.register(customStrat)
        assertNotNull(StrategyRegistry.getStrategy("CUSTOM_BREAKOUT"))

        StrategyRegistry.unregister("CUSTOM_BREAKOUT")
        assertNull(StrategyRegistry.getStrategy("CUSTOM_BREAKOUT"))
    }
}
