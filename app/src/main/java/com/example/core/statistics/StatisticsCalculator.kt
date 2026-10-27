package com.example.core.statistics

import com.example.core.model.DailySummary
import com.example.core.model.EquityPoint
import com.example.core.model.PerformanceMetrics
import com.example.core.model.TradeJournalEntry
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

object StatisticsCalculator {

    fun calculate(
        initialBalance: Double,
        trades: List<TradeJournalEntry>,
        currentEquity: Double? = null
    ): PerformanceMetrics {
        if (trades.isEmpty()) {
            val bal = initialBalance
            val eq = currentEquity ?: initialBalance
            return PerformanceMetrics(
                initialBalance = bal,
                finalBalance = bal,
                equity = eq,
                netProfit = 0.0,
                returnPct = 0.0,
                grossProfit = 0.0,
                grossLoss = 0.0,
                profitFactor = null,
                winRatePct = 0.0,
                totalTrades = 0,
                winningTrades = 0,
                losingTrades = 0,
                avgWin = null,
                avgLoss = null,
                expectancy = null,
                maxDrawdown = 0.0,
                maxDrawdownPct = 0.0,
                maxConsecutiveWins = 0,
                maxConsecutiveLosses = 0,
                bestTrade = null,
                worstTrade = null,
                avgDurationMillis = 0,
                totalVolume = 0.0,
                avgRMultiple = null,
                sharpeRatio = null,
                sortinoRatio = null,
                recoveryFactor = null
            )
        }

        var balance = initialBalance
        var grossProfit = 0.0
        var grossLoss = 0.0
        var winningTrades = 0
        var losingTrades = 0
        var totalVolume = 0.0
        var totalDuration = 0L
        var totalRMultiple = 0.0
        var rCount = 0

        var bestTrade: Double? = null
        var worstTrade: Double? = null

        var currentConsecutiveWins = 0
        var maxConsecutiveWins = 0
        var currentConsecutiveLosses = 0
        var maxConsecutiveLosses = 0

        var highWatermark = initialBalance
        var maxDrawdown = 0.0
        var maxDrawdownPct = 0.0

        val returns = mutableListOf<Double>()

        for (trade in trades) {
            val net = trade.netProfitLoss
            val prevBalance = balance
            balance += net
            totalVolume += trade.volume
            totalDuration += trade.durationMillis

            if (trade.rMultiple != 0.0) {
                totalRMultiple += trade.rMultiple
                rCount++
            }

            if (prevBalance > 0) {
                returns.add(net / prevBalance)
            }

            if (net > 0) {
                grossProfit += net
                winningTrades++
                currentConsecutiveWins++
                currentConsecutiveLosses = 0
                maxConsecutiveWins = max(maxConsecutiveWins, currentConsecutiveWins)
            } else if (net < 0) {
                grossLoss += abs(net)
                losingTrades++
                currentConsecutiveLosses++
                currentConsecutiveWins = 0
                maxConsecutiveLosses = max(maxConsecutiveLosses, currentConsecutiveLosses)
            }

            if (bestTrade == null || net > bestTrade) bestTrade = net
            if (worstTrade == null || net < worstTrade) worstTrade = net

            if (balance > highWatermark) {
                highWatermark = balance
            }
            val dd = highWatermark - balance
            val ddPct = if (highWatermark > 0) (dd / highWatermark) * 100.0 else 0.0
            if (dd > maxDrawdown) maxDrawdown = dd
            if (ddPct > maxDrawdownPct) maxDrawdownPct = ddPct
        }

        val netProfit = balance - initialBalance
        val returnPct = if (initialBalance > 0) (netProfit / initialBalance) * 100.0 else 0.0
        val totalTrades = trades.size
        val winRatePct = if (totalTrades > 0) (winningTrades.toDouble() / totalTrades) * 100.0 else 0.0

        val profitFactor = if (grossLoss > 0.0) {
            grossProfit / grossLoss
        } else if (grossProfit > 0.0) {
            null // Infinite / undefined statistically
        } else {
            0.0
        }

        val avgWin = if (winningTrades > 0) grossProfit / winningTrades else null
        val avgLoss = if (losingTrades > 0) grossLoss / losingTrades else null

        // Mean net result per closed trade, including losses and breakeven trades.
        val expectancy = if (totalTrades > 0) trades.sumOf { it.netProfitLoss } / totalTrades else null

        val avgRMultiple = if (rCount > 0) totalRMultiple / rCount else null
        val avgDuration = if (totalTrades > 0) totalDuration / totalTrades else 0L

        // Sharpe & Sortino calculation
        val sharpeRatio = if (returns.size >= 3) {
            val meanReturn = returns.average()
            val variance = returns.map { (it - meanReturn) * (it - meanReturn) }.average()
            val stdDev = sqrt(variance)
            if (stdDev > 0) (meanReturn / stdDev) * sqrt(252.0) else null
        } else null

        val sortinoRatio = if (returns.size >= 3) {
            val meanReturn = returns.average()
            val negativeReturns = returns.filter { it < 0 }
            if (negativeReturns.isNotEmpty()) {
                val downVariance = negativeReturns.map { it * it }.average()
                val downStdDev = sqrt(downVariance)
                if (downStdDev > 0) (meanReturn / downStdDev) * sqrt(252.0) else null
            } else null
        } else null

        val recoveryFactor = if (maxDrawdown > 0.0) netProfit / maxDrawdown else null

        val shortestDuration = trades.minOfOrNull { it.durationMillis } ?: 0L
        val longestDuration = trades.maxOfOrNull { it.durationMillis } ?: 0L
        val avgVolume = if (totalTrades > 0) totalVolume / totalTrades else 0.0
        val largestVol = trades.maxOfOrNull { it.volume } ?: 0.0
        val smallestVol = trades.minOfOrNull { it.volume } ?: 0.0

        val bestTradeRecord = trades.maxByOrNull { it.netProfitLoss }
        val worstTradeRecord = trades.minByOrNull { it.netProfitLoss }

        // Risk calculations based on recorded SL distances
        val tradesWithRisk = trades.filter { it.stopLoss != null }
        val avgRiskAmount = if (tradesWithRisk.isNotEmpty()) {
            val totalRisk = tradesWithRisk.sumOf { t ->
                val sym = com.example.core.market.DefaultSymbols.getSymbol(t.symbol)
                abs(t.entryPrice - t.stopLoss!!) * t.volume * sym.contractSize
            }
            totalRisk / tradesWithRisk.size
        } else null

        val avgRiskPct = if (avgRiskAmount != null && initialBalance > 0.0) {
            (avgRiskAmount / initialBalance) * 100.0
        } else null

        return PerformanceMetrics(
            initialBalance = initialBalance,
            finalBalance = balance,
            equity = currentEquity ?: balance,
            netProfit = netProfit,
            returnPct = returnPct,
            grossProfit = grossProfit,
            grossLoss = grossLoss,
            profitFactor = profitFactor,
            winRatePct = winRatePct,
            totalTrades = totalTrades,
            winningTrades = winningTrades,
            losingTrades = losingTrades,
            avgWin = avgWin,
            avgLoss = avgLoss,
            expectancy = expectancy,
            maxDrawdown = maxDrawdown,
            maxDrawdownPct = maxDrawdownPct,
            maxConsecutiveWins = maxConsecutiveWins,
            maxConsecutiveLosses = maxConsecutiveLosses,
            bestTrade = bestTrade,
            worstTrade = worstTrade,
            avgDurationMillis = avgDuration,
            totalVolume = totalVolume,
            avgRMultiple = avgRMultiple,
            sharpeRatio = sharpeRatio,
            sortinoRatio = sortinoRatio,
            recoveryFactor = recoveryFactor,
            shortestDurationMillis = shortestDuration,
            longestDurationMillis = longestDuration,
            avgVolume = avgVolume,
            largestVolume = largestVol,
            smallestVolume = smallestVol,
            avgRiskAmount = avgRiskAmount,
            avgRiskPct = avgRiskPct,
            bestTradeRecord = bestTradeRecord,
            worstTradeRecord = worstTradeRecord
        )
    }

    /**
     * Generates time-series equity points for charts.
     */
    fun buildEquityCurve(
        initialBalance: Double,
        trades: List<TradeJournalEntry>
    ): List<EquityPoint> {
        val points = mutableListOf<EquityPoint>()
        var currentBalance = initialBalance
        var highWatermark = initialBalance

        // Add starting point
        val firstTime = trades.firstOrNull()?.openTime ?: System.currentTimeMillis()
        points.add(
            EquityPoint(
                timestamp = firstTime - 1000,
                balance = initialBalance,
                equity = initialBalance,
                drawdown = 0.0,
                highWatermark = initialBalance
            )
        )

        for (trade in trades.sortedBy { it.closeTime }) {
            currentBalance += trade.netProfitLoss
            if (currentBalance > highWatermark) {
                highWatermark = currentBalance
            }
            val dd = highWatermark - currentBalance
            points.add(
                EquityPoint(
                    timestamp = trade.closeTime,
                    balance = currentBalance,
                    equity = currentBalance,
                    drawdown = dd,
                    highWatermark = highWatermark
                )
            )
        }

        return points
    }

    /**
     * Calculates daily aggregated summaries from completed trade journal entries.
     */
    fun calculateDailySummaries(trades: List<TradeJournalEntry>): List<DailySummary> {
        val sdfShort = java.text.SimpleDateFormat("dd/MM", java.util.Locale.US)
        val sdfFull = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)

        val grouped = trades.groupBy { sdfFull.format(java.util.Date(it.closeTime)) }
        return grouped.map { (dateKey, dayTrades) ->
            val pl = dayTrades.sumOf { it.netProfitLoss }
            val lots = dayTrades.sumOf { it.volume }
            val wins = dayTrades.count { it.netProfitLoss > 0 }
            val wr = if (dayTrades.isNotEmpty()) (wins.toDouble() / dayTrades.size) * 100.0 else 0.0
            val shortDate = if (dayTrades.isNotEmpty()) sdfShort.format(java.util.Date(dayTrades.first().closeTime)) else dateKey

            DailySummary(
                dateStr = shortDate,
                fullDate = dateKey,
                profitLoss = pl,
                tradeCount = dayTrades.size,
                totalLots = lots,
                winRatePct = wr
            )
        }.sortedByDescending { it.fullDate }
    }
}
