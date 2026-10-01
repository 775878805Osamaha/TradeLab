package com.example

import com.example.core.backtest.BacktestConfig
import com.example.core.backtest.BacktestEngine
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
    fun `test StrategyRegistry registers built-in strategies and default presets`() {
        val all = StrategyRegistry.getAllStrategies()
        assertTrue("Must contain at least 4 built-in strategies", all.size >= 4)

        assertNotNull(StrategyRegistry.getStrategy("EMA_CROSSOVER"))
        assertNotNull(StrategyRegistry.getStrategy("SMA_CROSSOVER"))
        assertNotNull(StrategyRegistry.getStrategy("RSI_REVERSION"))
        assertNotNull(StrategyRegistry.getStrategy("BOLLINGER_REVERSION"))

        val emaPresets = StrategyRegistry.getPresetsForStrategy("EMA_CROSSOVER")
        assertTrue("EMA must have presets", emaPresets.isNotEmpty())
        assertTrue(emaPresets.any { it.isDefault })
    }

    @Test
    fun `test StrategyFactory creates and resets strategy instance`() {
        val strat = StrategyFactory.createStrategy("EMA_CROSSOVER")
        assertNotNull(strat)
        assertEquals("EMA_CROSSOVER", strat!!.id)
        assertEquals(StrategyCategory.TREND, strat.category)
        assertEquals(1, strat.version)
    }

    @Test
    fun `test StrategyValidator validates parameter boundaries and cross-field rules`() {
        val ema = EmaCrossoverStrategy()

        // Valid parameters
        val validRes = StrategyValidator.validate(ema, mapOf("fastPeriod" to 9, "slowPeriod" to 21))
        assertTrue(validRes.isValid)
        assertTrue(validRes.errors.isEmpty())

        // Invalid: fast >= slow
        val invalidCrossover = StrategyValidator.validate(ema, mapOf("fastPeriod" to 25, "slowPeriod" to 10))
        assertFalse(invalidCrossover.isValid)
        assertTrue(invalidCrossover.errors.any { it.field == "slowPeriod" })

        // RSI validations
        val rsi = RsiMeanReversionStrategy()
        val badRsi = StrategyValidator.validate(rsi, mapOf("oversoldLevel" to 60.0, "overboughtLevel" to 40.0))
        assertFalse(badRsi.isValid)
        assertTrue(badRsi.errors.any { it.field == "oversoldLevel" })
        assertTrue(badRsi.errors.any { it.field == "overboughtLevel" })
    }

    @Test
    fun `test duplicate signal prevention for the same candle bar`() {
        val ema = EmaCrossoverStrategy()
        ema.reset()

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
        val firstSignal = ema.onCandle(context, ema.defaultParameters)

        // If it was a trade signal, second call with the exact same candle MUST return HOLD
        if (firstSignal.action != SignalAction.HOLD) {
            val secondSignal = ema.onCandle(context, ema.defaultParameters)
            assertEquals("Duplicate signal on same bar must return HOLD", SignalAction.HOLD, secondSignal.action)
        }
    }

    @Test
    fun `test strategy position awareness prevents re-entering same direction`() {
        val ema = EmaCrossoverStrategy()
        ema.reset()

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

        val signal = ema.onCandle(contextWithLong, ema.defaultParameters)
        // Must NOT emit duplicate BUY while already positioned Long
        assertNotEquals("Should not emit duplicate BUY while already long", SignalAction.BUY, signal.action)
    }

    @Test
    fun `test strategy state reset allows fresh evaluation`() {
        val ema = EmaCrossoverStrategy()
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

        val sig1 = ema.onCandle(context, ema.defaultParameters)
        // Reset strategy internal state
        ema.reset()

        // Calling onCandle after reset on same context behaves identically to first execution
        val sig2 = ema.onCandle(context, ema.defaultParameters)
        assertEquals(sig1.action, sig2.action)
    }

    @Test
    fun `test Strategy determinism across identical evaluations`() {
        val sma = SmaCrossoverStrategy()
        sma.reset()
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

        val sig1 = sma.onCandle(context1, sma.defaultParameters)

        sma.reset()
        val context2 = StrategyContext(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            currentCandle = current,
            historicalCandles = candles,
            openPositions = emptyList(),
            account = VirtualAccount(id = 1, name = "Test", balance = 100.0)
        )

        val sig2 = sma.onCandle(context2, sma.defaultParameters)

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

        // At M5 time 5,000,000 ms:
        // H1 candle 1 (closed at 3.6m) is COMPLETED.
        // H1 candle 2 (closes at 7.2m) is STILL FORMING (in progress).
        // H1 candle 3 (closes at 10.8m) is in the FUTURE.
        val completedAt5m = mtfProvider.getCompletedHtfCandles(currentExecutionTimestamp = 5000000L)

        assertEquals("Only completed H1 candles must be accessible", 1, completedAt5m.size)
        assertEquals(3600000L, completedAt5m.first().closeTime)

        val latest = mtfProvider.getLatestClosedHtfCandle(currentExecutionTimestamp = 5000000L)
        assertNotNull(latest)
        assertEquals(104.0, latest!!.close, 0.001)

        // At M5 time 7,500,000 ms:
        // H1 candle 1 and 2 are completed
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

        // Current execution time is 5,000,000 ms (before candle closes at 7,200,000 ms)
        try {
            mtfProvider.enforceNoLookahead(h1CandleFuture, currentExecutionTimestamp = 5000000L)
            fail("Expected HtfLookaheadViolation when accessing unclosed HTF candle")
        } catch (e: HtfLookaheadViolation) {
            assertTrue(e.message?.contains("Access Denied") == true)
        }
    }

    @Test
    fun `test BacktestEngine integration with all 4 built-in strategies`() = runBlocking {
        val candles = generateCandleSeries(count = 70, trend = 0.5, waveAmplitude = 3.0)

        val strategies = listOf(
            EmaCrossoverStrategy(),
            SmaCrossoverStrategy(),
            RsiMeanReversionStrategy(),
            BollingerMeanReversionStrategy()
        )

        for (strat in strategies) {
            strat.reset()
            val config = BacktestConfig(
                strategy = strat,
                symbol = "XAUUSD",
                timeframe = Timeframe.M15,
                initialBalance = 100.0,
                fixedLot = 0.01
            )

            val result = backtestEngine.runBacktest(candles, config)
            assertNotNull("Backtest result for ${strat.name} must not be null", result)
            assertEquals(70, result.totalCandlesProcessed)
            assertNotNull(result.metrics)
            assertTrue("Equity curve must be populated", result.equityCurve.isNotEmpty())
        }
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
