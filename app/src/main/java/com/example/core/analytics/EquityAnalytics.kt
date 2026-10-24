package com.example.core.analytics

import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Deterministic analytics over closed, chronological equity observations.
 * Does not infer fills, interpolate missing bars, or use synthetic prices.
 */
object EquityAnalytics {
    data class Point(val timestampMillis: Long, val equity: Double)
    data class Drawdown(val peakIndex: Int, val troughIndex: Int, val amount: Double, val percent: Double)
    data class Summary(
        val observations: Int,
        val initialEquity: Double,
        val finalEquity: Double,
        val netProfit: Double,
        val returnPercent: Double,
        val maxDrawdown: Drawdown,
        val positivePeriods: Int,
        val negativePeriods: Int,
        val flatPeriods: Int,
        val periodWinRatePercent: Double,
        val meanPeriodReturnPercent: Double,
        val periodReturnStdDevPercent: Double,
        val recoveryFactor: Double?,
        val longestLosingStreak: Int,
        val longestWinningStreak: Int
    )

    fun summarize(points: List<Point>): Summary? {
        if (points.isEmpty()) return null
        require(points.all { it.equity.isFinite() && it.equity > 0.0 && it.timestampMillis >= 0L }) {
            "Equity observations must be finite, positive, and timestamped"
        }
        require(points.zipWithNext().all { (a, b) -> b.timestampMillis > a.timestampMillis }) {
            "Equity observations must be strictly chronological"
        }
        var peak = points[0].equity
        var peakIndex = 0
        var maxDrawdown = Drawdown(0, 0, 0.0, 0.0)
        var positive = 0
        var negative = 0
        var flat = 0
        var winningStreak = 0
        var losingStreak = 0
        var longestWin = 0
        var longestLoss = 0
        val returns = ArrayList<Double>(points.size - 1)
        points.forEachIndexed { index, point ->
            if (point.equity > peak) {
                peak = point.equity
                peakIndex = index
            }
            val amount = peak - point.equity
            val pct = amount / peak * 100.0
            if (pct > maxDrawdown.percent) {
                maxDrawdown = Drawdown(peakIndex, index, amount, pct)
            }
            if (index > 0) {
                val previous = points[index - 1].equity
                val change = (point.equity / previous - 1.0) * 100.0
                require(change.isFinite()) { "Period return overflow" }
                returns.add(change)
                when {
                    change > 0.0 -> {
                        positive++
                        winningStreak++
                        losingStreak = 0
                        longestWin = maxOf(longestWin, winningStreak)
                    }
                    change < 0.0 -> {
                        negative++
                        losingStreak++
                        winningStreak = 0
                        longestLoss = maxOf(longestLoss, losingStreak)
                    }
                    else -> {
                        flat++
                        winningStreak = 0
                        losingStreak = 0
                    }
                }
            }
        }
        val mean = if (returns.isEmpty()) 0.0 else returns.average()
        val variance = if (returns.isEmpty()) 0.0 else returns.sumOf { (it - mean) * (it - mean) } / returns.size
        val net = points.last().equity - points.first().equity
        val totalReturn = (points.last().equity / points.first().equity - 1.0) * 100.0
        require(net.isFinite() && totalReturn.isFinite() && variance.isFinite()) { "Analytics overflow" }
        return Summary(
            observations = points.size,
            initialEquity = points.first().equity,
            finalEquity = points.last().equity,
            netProfit = net,
            returnPercent = totalReturn,
            maxDrawdown = maxDrawdown,
            positivePeriods = positive,
            negativePeriods = negative,
            flatPeriods = flat,
            periodWinRatePercent = if (positive + negative == 0) 0.0 else positive * 100.0 / (positive + negative),
            meanPeriodReturnPercent = mean,
            periodReturnStdDevPercent = sqrt(variance),
            recoveryFactor = if (maxDrawdown.amount > 0.0) net / maxDrawdown.amount else null,
            longestLosingStreak = longestLoss,
            longestWinningStreak = longestWin
        )
    }
}
