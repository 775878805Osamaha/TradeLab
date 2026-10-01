package com.example

import com.example.core.export.ResultsExporter
import com.example.core.model.*
import com.example.core.statistics.StatisticsCalculator
import org.junit.Assert.*
import org.junit.Test

class AnalyticsEngineTests {

    private fun createTrade(
        id: Long,
        symbol: String = "XAUUSD",
        side: PositionSide = PositionSide.BUY,
        volume: Double = 0.01,
        entryPrice: Double = 2650.0,
        exitPrice: Double = 2660.0,
        stopLoss: Double? = 2640.0,
        takeProfit: Double? = 2670.0,
        netProfitLoss: Double = 10.0,
        openTime: Long = 1700000000000L,
        closeTime: Long = 1700003600000L,
        exitReason: ExitReason = ExitReason.TAKE_PROFIT,
        rMultiple: Double = 1.0
    ): TradeJournalEntry = TradeJournalEntry(
        id = id,
        accountId = 1L,
        symbol = symbol,
        side = side,
        volume = volume,
        entryPrice = entryPrice,
        exitPrice = exitPrice,
        stopLoss = stopLoss,
        takeProfit = takeProfit,
        profitLoss = netProfitLoss,
        commission = 0.0,
        swap = 0.0,
        netProfitLoss = netProfitLoss,
        openTime = openTime,
        closeTime = closeTime,
        strategyId = "TEST_STRAT",
        exitReason = exitReason,
        rMultiple = rMultiple,
        mode = "BACKTEST"
    )

    @Test
    fun `test StatisticsCalculator with zero trades returns safe values without NaN or Infinity`() {
        val metrics = StatisticsCalculator.calculate(
            initialBalance = 100.0,
            trades = emptyList()
        )

        assertEquals(100.0, metrics.initialBalance, 0.001)
        assertEquals(100.0, metrics.finalBalance, 0.001)
        assertEquals(0.0, metrics.netProfit, 0.001)
        assertEquals(0.0, metrics.returnPct, 0.001)
        assertEquals(0.0, metrics.grossProfit, 0.001)
        assertEquals(0.0, metrics.grossLoss, 0.001)
        assertNull("Profit factor must be null when no trades exist", metrics.profitFactor)
        assertEquals(0, metrics.totalTrades)
        assertEquals(0.0, metrics.winRatePct, 0.001)
        assertNull("Expectancy must be null when no trades exist", metrics.expectancy)
        assertEquals(0.0, metrics.maxDrawdown, 0.001)
        assertEquals(0.0, metrics.maxDrawdownPct, 0.001)
        assertNull("Sharpe ratio must be null when insufficient data", metrics.sharpeRatio)
        assertNull("Sortino ratio must be null when insufficient data", metrics.sortinoRatio)
        assertNull("Recovery factor must be null when max drawdown is 0", metrics.recoveryFactor)
        assertFalse("No field should be NaN", metrics.netProfit.isNaN())
        assertFalse("No field should be Infinity", metrics.netProfit.isInfinite())
    }

    @Test
    fun `test StatisticsCalculator with single winning trade handles zero gross loss safely`() {
        val trades = listOf(
            createTrade(id = 1, netProfitLoss = 25.0)
        )

        val metrics = StatisticsCalculator.calculate(
            initialBalance = 100.0,
            trades = trades
        )

        assertEquals(125.0, metrics.finalBalance, 0.001)
        assertEquals(25.0, metrics.netProfit, 0.001)
        assertEquals(25.0, metrics.grossProfit, 0.001)
        assertEquals(0.0, metrics.grossLoss, 0.001)
        assertNull("Profit factor must be null (not Infinity!) when grossLoss is 0", metrics.profitFactor)
        assertEquals(100.0, metrics.winRatePct, 0.001)
        assertEquals(1, metrics.winningTrades)
        assertEquals(0, metrics.losingTrades)
        assertEquals(1, metrics.maxConsecutiveWins)
        assertEquals(0, metrics.maxConsecutiveLosses)
        assertEquals(25.0, metrics.bestTrade!!, 0.001)
        assertEquals(25.0, metrics.worstTrade!!, 0.001)
    }

    @Test
    fun `test StatisticsCalculator with single losing trade`() {
        val trades = listOf(
            createTrade(id = 1, netProfitLoss = -15.0, exitReason = ExitReason.STOP_LOSS)
        )

        val metrics = StatisticsCalculator.calculate(
            initialBalance = 100.0,
            trades = trades
        )

        assertEquals(85.0, metrics.finalBalance, 0.001)
        assertEquals(-15.0, metrics.netProfit, 0.001)
        assertEquals(0.0, metrics.grossProfit, 0.001)
        assertEquals(15.0, metrics.grossLoss, 0.001)
        assertEquals(0.0, metrics.profitFactor!!, 0.001)
        assertEquals(0.0, metrics.winRatePct, 0.001)
        assertEquals(0, metrics.winningTrades)
        assertEquals(1, metrics.losingTrades)
        assertEquals(0, metrics.maxConsecutiveWins)
        assertEquals(1, metrics.maxConsecutiveLosses)
        assertEquals(15.0, metrics.maxDrawdown, 0.001)
        assertEquals(15.0, metrics.maxDrawdownPct, 0.001)
    }

    @Test
    fun `test StatisticsCalculator with all wins has zero drawdown and null recovery factor`() {
        val trades = listOf(
            createTrade(id = 1, netProfitLoss = 10.0),
            createTrade(id = 2, netProfitLoss = 20.0),
            createTrade(id = 3, netProfitLoss = 15.0)
        )

        val metrics = StatisticsCalculator.calculate(100.0, trades)
        assertEquals(145.0, metrics.finalBalance, 0.001)
        assertEquals(45.0, metrics.netProfit, 0.001)
        assertEquals(0.0, metrics.maxDrawdown, 0.001)
        assertNull("Recovery factor must be null (not Infinity!) when max drawdown is 0", metrics.recoveryFactor)
        assertEquals(3, metrics.maxConsecutiveWins)
    }

    @Test
    fun `test StatisticsCalculator with mixed trades and consecutive tracking`() {
        val trades = listOf(
            createTrade(id = 1, netProfitLoss = 10.0),
            createTrade(id = 2, netProfitLoss = 15.0),
            createTrade(id = 3, netProfitLoss = -8.0),
            createTrade(id = 4, netProfitLoss = -12.0),
            createTrade(id = 5, netProfitLoss = -5.0),
            createTrade(id = 6, netProfitLoss = 20.0)
        )

        val metrics = StatisticsCalculator.calculate(100.0, trades)
        assertEquals(6, metrics.totalTrades)
        assertEquals(3, metrics.winningTrades)
        assertEquals(3, metrics.losingTrades)
        assertEquals(50.0, metrics.winRatePct, 0.001)
        assertEquals(2, metrics.maxConsecutiveWins)
        assertEquals(3, metrics.maxConsecutiveLosses)
        assertEquals(45.0, metrics.grossProfit, 0.001) // 10 + 15 + 20
        assertEquals(25.0, metrics.grossLoss, 0.001) // 8 + 12 + 5
        assertEquals(45.0 / 25.0, metrics.profitFactor!!, 0.001)
        assertEquals(20.0, metrics.bestTrade!!, 0.001)
        assertEquals(-12.0, metrics.worstTrade!!, 0.001)
    }

    @Test
    fun `test Sharpe and Sortino ratio require minimum observations`() {
        // Only 2 trades: insufficient data
        val twoTrades = listOf(
            createTrade(id = 1, netProfitLoss = 10.0),
            createTrade(id = 2, netProfitLoss = -5.0)
        )
        val m1 = StatisticsCalculator.calculate(100.0, twoTrades)
        assertNull("Sharpe must be null with < 3 observations", m1.sharpeRatio)
        assertNull("Sortino must be null with < 3 observations", m1.sortinoRatio)

        // 4 trades with variation: valid
        val fourTrades = listOf(
            createTrade(id = 1, netProfitLoss = 10.0),
            createTrade(id = 2, netProfitLoss = -5.0),
            createTrade(id = 3, netProfitLoss = 8.0),
            createTrade(id = 4, netProfitLoss = -3.0)
        )
        val m2 = StatisticsCalculator.calculate(100.0, fourTrades)
        assertNotNull("Sharpe must be calculated with >= 3 observations", m2.sharpeRatio)
        assertNotNull("Sortino must be calculated with >= 3 observations and downside variance", m2.sortinoRatio)
        assertTrue("Sharpe must be finite", !m2.sharpeRatio!!.isNaN() && !m2.sharpeRatio!!.isInfinite())
        assertTrue("Sortino must be finite", !m2.sortinoRatio!!.isNaN() && !m2.sortinoRatio!!.isInfinite())
    }

    @Test
    fun `test duration and volume analytics`() {
        val trades = listOf(
            createTrade(id = 1, volume = 0.01, openTime = 1000L, closeTime = 4000L), // 3000 ms
            createTrade(id = 2, volume = 0.05, openTime = 5000L, closeTime = 15000L), // 10000 ms
            createTrade(id = 3, volume = 0.02, openTime = 20000L, closeTime = 22000L) // 2000 ms
        )

        val metrics = StatisticsCalculator.calculate(100.0, trades)
        assertEquals(3000L + 10000L + 2000L, trades.sumOf { it.durationMillis })
        assertEquals(5000L, metrics.avgDurationMillis)
        assertEquals(2000L, metrics.shortestDurationMillis)
        assertEquals(10000L, metrics.longestDurationMillis)
        assertEquals(0.08, metrics.totalVolume, 0.001)
        assertEquals(0.08 / 3, metrics.avgVolume, 0.001)
        assertEquals(0.05, metrics.largestVolume, 0.001)
        assertEquals(0.01, metrics.smallestVolume, 0.001)
    }

    @Test
    fun `test daily summaries calculation`() {
        // 2 trades on day 1 (2026-09-20), 1 trade on day 2 (2026-09-21)
        val t1 = createTrade(id = 1, netProfitLoss = 15.0, closeTime = 1790000000000L)
        val t2 = createTrade(id = 2, netProfitLoss = -5.0, closeTime = 1790003600000L)
        val t3 = createTrade(id = 3, netProfitLoss = 20.0, closeTime = 1790100000000L)

        val daily = StatisticsCalculator.calculateDailySummaries(listOf(t1, t2, t3))
        assertEquals(2, daily.size)

        val dayWithTwoTrades = daily.firstOrNull { it.tradeCount == 2 }
        assertNotNull(dayWithTwoTrades)
        assertEquals(10.0, dayWithTwoTrades!!.profitLoss, 0.001)
        assertEquals(50.0, dayWithTwoTrades.winRatePct, 0.001)
    }

    @Test
    fun `test ResultsExporter formats CSV and JSON without errors`() {
        val trades = listOf(
            createTrade(id = 1, netProfitLoss = 12.0),
            createTrade(id = 2, netProfitLoss = -4.0)
        )
        val metrics = StatisticsCalculator.calculate(100.0, trades)
        val daily = StatisticsCalculator.calculateDailySummaries(trades)
        val points = StatisticsCalculator.buildEquityCurve(100.0, trades)

        val csvSummary = ResultsExporter.exportSummaryCsv(metrics, "EMA Crossover", "XAUUSD", "M15")
        assertTrue(csvSummary.contains("Metric,Value"))
        assertTrue(csvSummary.contains("EMA Crossover"))
        assertTrue(csvSummary.contains("Initial Balance,100.00"))

        val csvTrades = ResultsExporter.exportTradesCsv(trades)
        assertTrue(csvTrades.contains("ID,Symbol,Side,Volume"))
        assertTrue(csvTrades.contains("XAUUSD,BUY"))

        val csvDaily = ResultsExporter.exportDailyResultsCsv(daily)
        assertTrue(csvDaily.contains("Date,Net PL,Trade Count"))

        val csvEquity = ResultsExporter.exportEquityPointsCsv(points)
        assertTrue(csvEquity.contains("Timestamp,Datetime,Balance,Equity"))

        val json = ResultsExporter.exportCompleteJson(metrics, trades, daily, points, "EMA Crossover", "XAUUSD", "M15")
        assertTrue(json.contains("\"strategy\": \"EMA Crossover\""))
        assertTrue(json.contains("\"initialBalance\": 100.0"))
        assertTrue(json.contains("\"tradesCount\": 2"))
    }

    @Test
    fun `test ResultsExporter with empty dataset`() {
        val emptyMetrics = StatisticsCalculator.calculate(100.0, emptyList())
        val csv = ResultsExporter.exportSummaryCsv(emptyMetrics)
        assertTrue(csv.contains("Profit Factor,N/A"))
        assertTrue(csv.contains("Sharpe Ratio,N/A"))

        val json = ResultsExporter.exportCompleteJson(emptyMetrics, emptyList(), emptyList(), emptyList())
        assertTrue(json.contains("\"profitFactor\": null"))
        assertTrue(json.contains("\"sharpeRatio\": null"))
        assertTrue(json.contains("\"tradesCount\": 0"))
    }

    @Test
    fun `test buildEquityCurve with zero trades and one trade`() {
        val pointsZero = StatisticsCalculator.buildEquityCurve(100.0, emptyList())
        assertEquals(1, pointsZero.size)
        assertEquals(100.0, pointsZero[0].balance, 0.001)

        val oneTrade = listOf(createTrade(id = 1, netProfitLoss = 20.0))
        val pointsOne = StatisticsCalculator.buildEquityCurve(100.0, oneTrade)
        assertEquals(2, pointsOne.size)
        assertEquals(100.0, pointsOne[0].balance, 0.001)
        assertEquals(120.0, pointsOne[1].balance, 0.001)
    }
}
