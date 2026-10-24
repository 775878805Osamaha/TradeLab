package com.example.core.analytics

import java.util.Locale

/**
 * Deterministic, locale-invariant CSV export for validated backtest equity curves.
 * Exports only supplied observations; never interpolates gaps or invents trades.
 */
object EquityCsvExporter {
    fun export(points: List<EquityAnalytics.Point>): String {
        if (points.isEmpty()) return "timestamp_ms,equity,change_usd,return_percent,drawdown_usd,drawdown_percent\n"
        // Reuse the same chronological and numeric validation as the analytics engine.
        requireNotNull(EquityAnalytics.summarize(points))
        return buildString {
            append("timestamp_ms,equity,change_usd,return_percent,drawdown_usd,drawdown_percent\n")
            var peak = points.first().equity
            points.forEachIndexed { index, point ->
                peak = maxOf(peak, point.equity)
                val previous = if (index == 0) point.equity else points[index - 1].equity
                val change = point.equity - previous
                val periodReturn = if (index == 0) 0.0 else (point.equity / previous - 1.0) * 100.0
                val drawdown = peak - point.equity
                val drawdownPct = drawdown / peak * 100.0
                require(listOf(change, periodReturn, drawdown, drawdownPct).all { it.isFinite() }) {
                    "Equity export overflow"
                }
                append(point.timestampMillis)
                append(',')
                append(String.format(Locale.US, "%.8f", point.equity))
                append(',')
                append(String.format(Locale.US, "%.8f", change))
                append(',')
                append(String.format(Locale.US, "%.8f", periodReturn))
                append(',')
                append(String.format(Locale.US, "%.8f", drawdown))
                append(',')
                append(String.format(Locale.US, "%.8f", drawdownPct))
                append('\n')
            }
        }
    }

    fun exportSummary(summary: EquityAnalytics.Summary): String = buildString {
        append("metric,value\n")
        fun line(name: String, value: Number) {
            append(name).append(',').append(value.toString()).append('\n')
        }
        line("observations", summary.observations)
        line("initial_equity", summary.initialEquity)
        line("final_equity", summary.finalEquity)
        line("net_profit", summary.netProfit)
        line("return_percent", summary.returnPercent)
        line("max_drawdown_usd", summary.maxDrawdown.amount)
        line("max_drawdown_percent", summary.maxDrawdown.percent)
        line("drawdown_peak_index", summary.maxDrawdown.peakIndex)
        line("drawdown_trough_index", summary.maxDrawdown.troughIndex)
        line("positive_periods", summary.positivePeriods)
        line("negative_periods", summary.negativePeriods)
        line("flat_periods", summary.flatPeriods)
        line("period_win_rate_percent", summary.periodWinRatePercent)
        line("mean_period_return_percent", summary.meanPeriodReturnPercent)
        line("period_return_stddev_percent", summary.periodReturnStdDevPercent)
        summary.recoveryFactor?.let { line("recovery_factor", it) }
        line("longest_winning_streak", summary.longestWinningStreak)
        line("longest_losing_streak", summary.longestLosingStreak)
    }
}
