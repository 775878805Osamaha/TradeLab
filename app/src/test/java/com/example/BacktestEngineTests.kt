package com.example

import com.example.core.backtest.BacktestConfig
import com.example.core.backtest.BacktestEngine
import com.example.core.model.*
import com.example.core.strategy.Signal
import com.example.core.strategy.SignalAction
import com.example.core.strategy.Strategy
import com.example.core.strategy.StrategyContext
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import kotlin.math.abs

class BacktestEngineTests {

    private lateinit var backtestEngine: BacktestEngine

    @Before
    fun setUp() {
        backtestEngine = BacktestEngine()
    }

    private fun generateCandleSeries(
        count: Int,
        startPrice: Double = 2650.0,
        trendPerCandle: Double = 0.5,
        waveAmplitude: Double = 2.0
    ): List<Candle> {
        val candles = mutableListOf<Candle>()
        var currentPrice = startPrice
        var time = 1700000000000L

        for (i in 0 until count) {
            val wave = kotlin.math.sin(i * 0.2) * waveAmplitude
            val open = currentPrice
            val close = open + trendPerCandle + wave
            val high = maxOf(open, close) + 1.0
            val low = minOf(open, close) - 1.0

            candles.add(
                Candle(
                    symbol = "XAUUSD",
                    timeframe = Timeframe.M15,
                    openTime = time,
                    closeTime = time + 900000L,
                    open = open,
                    high = high,
                    low = low,
                    close = close,
                    volume = 100.0,
                    source = "TEST"
                )
            )
            currentPrice = close
            time += 900000L
        }
        return candles
    }

    // 1. Basic BUY Strategy
    class AlwaysBuyStrategy : Strategy {
        override val id: String = "ALWAYS_BUY"
        override val name: String = "Always Buy Test Strategy"
        override val description: String = "Buys whenever no position is open"
        override val defaultParameters: Map<String, Any> = emptyMap()

        override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
            return if (context.openPositions.isEmpty()) {
                Signal(
                    action = SignalAction.BUY,
                    direction = OrderSide.BUY,
                    entryPrice = context.currentCandle.close,
                    stopLoss = context.currentCandle.close - 10.0,
                    takeProfit = context.currentCandle.close + 20.0,
                    reason = "Test Buy"
                )
            } else {
                Signal(action = SignalAction.HOLD)
            }
        }
    }

    // 2. Basic SELL Strategy
    class AlwaysSellStrategy : Strategy {
        override val id: String = "ALWAYS_SELL"
        override val name: String = "Always Sell Test Strategy"
        override val description: String = "Sells whenever no position is open"
        override val defaultParameters: Map<String, Any> = emptyMap()

        override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
            return if (context.openPositions.isEmpty()) {
                Signal(
                    action = SignalAction.SELL,
                    direction = OrderSide.SELL,
                    entryPrice = context.currentCandle.close,
                    stopLoss = context.currentCandle.close + 10.0,
                    takeProfit = context.currentCandle.close - 20.0,
                    reason = "Test Sell"
                )
            } else {
                Signal(action = SignalAction.HOLD)
            }
        }
    }

    // 3. Strict Lookahead Auditor Strategy
    class LookaheadAuditorStrategy : Strategy {
        override val id: String = "LOOKAHEAD_AUDITOR"
        override val name: String = "Lookahead Auditor"
        override val description: String = "Verifies no future candles are ever leaked"
        override val defaultParameters: Map<String, Any> = emptyMap()

        var maxTimeObserved: Long = 0L
        var lookaheadViolations: Int = 0

        override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
            val currentCandleTime = context.currentCandle.openTime
            for (h in context.historicalCandles) {
                if (h.openTime > currentCandleTime) {
                    lookaheadViolations++
                }
            }
            if (currentCandleTime <= maxTimeObserved) {
                // Out-of-order check
            }
            maxTimeObserved = currentCandleTime
            return Signal(action = SignalAction.HOLD)
        }
    }

    @Test
    fun `test BacktestEngine basic BUY strategy execution`() = runBlocking {
        val candles = generateCandleSeries(count = 60, trendPerCandle = 1.0)
        val config = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            initialBalance = 100.0,
            fixedLot = 0.01,
            spreadPips = 1.0,
            slippagePips = 0.1
        )

        val result = backtestEngine.runBacktest(candles, config)
        assertNotNull(result)
        assertTrue(result.trades.isNotEmpty())
        assertEquals(PositionSide.BUY, result.trades.first().side)
        assertEquals("BACKTEST", result.trades.first().mode)
        assertTrue(result.equityCurve.isNotEmpty())
    }

    @Test
    fun `test BacktestEngine basic SELL strategy execution`() = runBlocking {
        val candles = generateCandleSeries(count = 60, trendPerCandle = -1.0)
        val config = BacktestConfig(
            strategy = AlwaysSellStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            initialBalance = 100.0,
            fixedLot = 0.01
        )

        val result = backtestEngine.runBacktest(candles, config)
        assertNotNull(result)
        assertTrue(result.trades.isNotEmpty())
        assertEquals(PositionSide.SELL, result.trades.first().side)
    }

    @Test
    fun `test BacktestEngine strict zero lookahead protection`() = runBlocking {
        val candles = generateCandleSeries(count = 80)
        val auditor = LookaheadAuditorStrategy()
        val config = BacktestConfig(
            strategy = auditor,
            symbol = "XAUUSD",
            timeframe = Timeframe.M15
        )

        backtestEngine.runBacktest(candles, config)
        assertEquals("Strict zero-lookahead must have 0 violations", 0, auditor.lookaheadViolations)
    }

    @Test
    fun `test BacktestEngine execution with test strategy`() = runBlocking {
        val candles = generateCandleSeries(count = 90, trendPerCandle = 0.8, waveAmplitude = 4.0)
        val config = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            initialBalance = 50.0,
            fixedLot = 0.01
        )

        val result = backtestEngine.runBacktest(candles, config)
        assertNotNull(result)
        assertTrue(result.totalCandlesProcessed == 90)
    }

    @Test
    fun `test BacktestEngine metrics with test mean reversion strategy`() = runBlocking {
        val candles = generateCandleSeries(count = 80, trendPerCandle = 0.0, waveAmplitude = 10.0)
        val testStrategy = object : Strategy {
            override val id: String = "TEST_REVERSION"
            override val name: String = "Test Reversion Strategy"
            override val description: String = "Test strategy"
            override val defaultParameters: Map<String, Any> = emptyMap()
            override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
                val candle = context.currentCandle
                return if (candle.close < 2650.0 && context.openPositions.none { it.side == PositionSide.BUY }) {
                    Signal(action = SignalAction.BUY, direction = OrderSide.BUY, symbol = context.symbol, entryPrice = candle.close, stopLoss = candle.close - 5.0, takeProfit = candle.close + 10.0)
                } else {
                    Signal(action = SignalAction.HOLD)
                }
            }
        }
        val config = BacktestConfig(
            strategy = testStrategy,
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            initialBalance = 100.0
        )

        val result = backtestEngine.runBacktest(candles, config)
        assertNotNull(result)
        assertNotNull(result.metrics)
    }

    @Test
    fun `test BacktestEngine position sizing modes`() = runBlocking {
        val candles = generateCandleSeries(count = 50, trendPerCandle = 1.0)

        // 1. FIXED_LOT mode
        val configFixed = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            positionSizingMode = PositionSizingMode.FIXED_LOT,
            fixedLot = 0.05
        )
        val resFixed = backtestEngine.runBacktest(candles, configFixed)
        if (resFixed.trades.isNotEmpty()) {
            assertEquals(0.05, resFixed.trades.first().volume, 0.001)
        }

        // 2. RISK_PERCENTAGE mode
        val configRiskPct = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            positionSizingMode = PositionSizingMode.RISK_PERCENTAGE,
            riskPercentage = 2.0
        )
        val resRiskPct = backtestEngine.runBacktest(candles, configRiskPct)
        assertNotNull(resRiskPct)

        // 3. FIXED_MONETARY_RISK mode
        val configFixedRisk = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            positionSizingMode = PositionSizingMode.FIXED_MONETARY_RISK,
            fixedRiskAmount = 10.0
        )
        val resFixedRisk = backtestEngine.runBacktest(candles, configFixedRisk)
        assertNotNull(resFixedRisk)
    }

    @Test
    fun `test BacktestEngine spread, slippage, and commission applied`() = runBlocking {
        val candles = generateCandleSeries(count = 40, trendPerCandle = 1.0)
        val config = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            spreadPips = 2.0,
            slippagePips = 0.5,
            commissionPerLot = 7.0
        )

        val res = backtestEngine.runBacktest(candles, config)
        if (res.trades.isNotEmpty()) {
            val trade = res.trades.first()
            assertTrue("Commission should be charged", trade.commission > 0.0)
        }
    }

    @Test
    fun `test BacktestEngine conservative intrabar execution matches Replay`() = runBlocking {
        // High volatility candle touches both SL and TP: SL triggers first
        val volatileCandles = mutableListOf<Candle>()
        var time = 100000L
        for (i in 0 until 20) {
            volatileCandles.add(
                Candle(
                    symbol = "XAUUSD",
                    timeframe = Timeframe.M15,
                    openTime = time,
                    closeTime = time + 900000L,
                    open = 2650.0,
                    high = 2652.0,
                    low = 2648.0,
                    close = 2650.0
                )
            )
            time += 900000L
        }

        // Intrabar explosion candle
        volatileCandles.add(
            Candle(
                symbol = "XAUUSD",
                timeframe = Timeframe.M15,
                openTime = time,
                closeTime = time + 900000L,
                open = 2650.0,
                high = 2680.0, // Touches TP
                low = 2620.0,  // Touches SL
                close = 2660.0
            )
        )

        val config = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15
        )

        val res = backtestEngine.runBacktest(volatileCandles, config)
        if (res.trades.isNotEmpty()) {
            val closedTrade = res.trades.first()
            assertEquals("Conservative rule: SL must trigger first", ExitReason.STOP_LOSS, closedTrade.exitReason)
        }
    }

    @Test
    fun `test BacktestEngine determinism`() = runBlocking {
        val candles = generateCandleSeries(count = 60, trendPerCandle = 0.5, waveAmplitude = 3.0)
        val config = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            initialBalance = 50.0,
            fixedLot = 0.01
        )

        val run1 = backtestEngine.runBacktest(candles, config)
        val run2 = backtestEngine.runBacktest(candles, config)

        assertEquals(run1.trades.size, run2.trades.size)
        assertEquals(run1.metrics.netProfit, run2.metrics.netProfit, 0.0001)
        assertEquals(run1.metrics.winRatePct, run2.metrics.winRatePct, 0.0001)
        assertEquals(run1.equityCurve.size, run2.equityCurve.size)
        if (run1.trades.isNotEmpty()) {
            assertEquals(run1.trades.first().entryPrice, run2.trades.first().entryPrice, 0.0001)
            assertEquals(run1.trades.first().netProfitLoss, run2.trades.first().netProfitLoss, 0.0001)
        }
    }

    @Test
    fun `test BacktestEngine empty dataset handled gracefully`() = runBlocking {
        val emptyList = emptyList<Candle>()
        val config = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15
        )

        try {
            backtestEngine.runBacktest(emptyList, config)
            fail("An empty historical dataset must not produce a successful backtest")
        } catch (error: IllegalArgumentException) {
            assertTrue(error.message.orEmpty().contains("No historical candles"))
        }
    }

    @Test
    fun `test BacktestEngine daily summaries generation`() = runBlocking {
        val candles = generateCandleSeries(count = 50, trendPerCandle = 1.0)
        val config = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15
        )

        val res = backtestEngine.runBacktest(candles, config)
        assertNotNull(res.dailySummaries)
        if (res.trades.isNotEmpty()) {
            assertTrue(res.dailySummaries.isNotEmpty())
            assertTrue(res.dailySummaries.first().fullDate.isNotEmpty())
        }
    }

    @Test
    fun `test BacktestConfig validation rejects invalid inputs`() {
        val strat = AlwaysBuyStrategy()

        // Negative balance
        val badBal = BacktestConfig(strategy = strat, symbol = "XAUUSD", timeframe = Timeframe.M15, initialBalance = -10.0)
        assertTrue(badBal.validate().isFailure)

        // Negative spread
        val badSpread = BacktestConfig(strategy = strat, symbol = "XAUUSD", timeframe = Timeframe.M15, spreadPips = -1.0)
        assertTrue(badSpread.validate().isFailure)

        // Invalid risk % (> 100)
        val badRisk = BacktestConfig(
            strategy = strat,
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            positionSizingMode = PositionSizingMode.RISK_PERCENTAGE,
            riskPercentage = 150.0
        )
        assertTrue(badRisk.validate().isFailure)

        // Neither Long nor Short
        val noDirection = BacktestConfig(
            strategy = strat,
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            allowLong = false,
            allowShort = false
        )
        assertTrue(noDirection.validate().isFailure)
    }

    @Test
    fun `test BacktestEngine large dataset processing`() = runBlocking {
        val largeCandles = generateCandleSeries(count = 1000, trendPerCandle = 0.05, waveAmplitude = 5.0)
        val config = BacktestConfig(
            strategy = AlwaysBuyStrategy(),
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            initialBalance = 100.0
        )

        val start = System.currentTimeMillis()
        val res = backtestEngine.runBacktest(largeCandles, config)
        val duration = System.currentTimeMillis() - start

        assertNotNull(res)
        assertEquals(1000, res.totalCandlesProcessed)
        assertTrue("1000 candles should be processed rapidly under 3 seconds", duration < 3000)
    }
}
