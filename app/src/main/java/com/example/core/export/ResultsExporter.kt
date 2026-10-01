package com.example.core.export

import com.example.core.model.DailySummary
import com.example.core.model.EquityPoint
import com.example.core.model.PerformanceMetrics
import com.example.core.model.TradeJournalEntry
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object ResultsExporter {

    private val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    fun exportSummaryCsv(
        metrics: PerformanceMetrics,
        strategyName: String = "N/A",
        symbol: String = "XAUUSD",
        timeframe: String = "M15"
    ): String {
        val sb = StringBuilder()
        sb.append("Metric,Value\n")
        sb.append("Strategy,${escapeCsv(strategyName)}\n")
        sb.append("Symbol,$symbol\n")
        sb.append("Timeframe,$timeframe\n")
        sb.append("Initial Balance,${String.format(Locale.US, "%.2f", metrics.initialBalance)}\n")
        sb.append("Final Balance,${String.format(Locale.US, "%.2f", metrics.finalBalance)}\n")
        sb.append("Net Profit,${String.format(Locale.US, "%.2f", metrics.netProfit)}\n")
        sb.append("Return %,${String.format(Locale.US, "%.2f%%", metrics.returnPct)}\n")
        sb.append("Gross Profit,${String.format(Locale.US, "%.2f", metrics.grossProfit)}\n")
        sb.append("Gross Loss,${String.format(Locale.US, "%.2f", metrics.grossLoss)}\n")
        sb.append("Profit Factor,${metrics.profitFactor?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A"}\n")
        sb.append("Total Trades,${metrics.totalTrades}\n")
        sb.append("Winning Trades,${metrics.winningTrades}\n")
        sb.append("Losing Trades,${metrics.losingTrades}\n")
        sb.append("Win Rate %,${String.format(Locale.US, "%.1f%%", metrics.winRatePct)}\n")
        sb.append("Average Win,${metrics.avgWin?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A"}\n")
        sb.append("Average Loss,${metrics.avgLoss?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A"}\n")
        sb.append("Expectancy,${metrics.expectancy?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A"}\n")
        sb.append("Max Drawdown $,${String.format(Locale.US, "%.2f", metrics.maxDrawdown)}\n")
        sb.append("Max Drawdown %,${String.format(Locale.US, "%.2f%%", metrics.maxDrawdownPct)}\n")
        sb.append("Max Consecutive Wins,${metrics.maxConsecutiveWins}\n")
        sb.append("Max Consecutive Losses,${metrics.maxConsecutiveLosses}\n")
        sb.append("Sharpe Ratio,${metrics.sharpeRatio?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A"}\n")
        sb.append("Sortino Ratio,${metrics.sortinoRatio?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A"}\n")
        sb.append("Recovery Factor,${metrics.recoveryFactor?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A"}\n")
        sb.append("Total Volume,${String.format(Locale.US, "%.2f", metrics.totalVolume)}\n")
        sb.append("Average Volume,${String.format(Locale.US, "%.2f", metrics.avgVolume)}\n")
        return sb.toString()
    }

    fun exportTradesCsv(trades: List<TradeJournalEntry>): String {
        val sb = StringBuilder()
        sb.append("ID,Symbol,Side,Volume,Entry Price,Exit Price,Stop Loss,Take Profit,Gross PL,Commission,Swap,Net PL,R Multiple,Open Time,Close Time,Duration (s),Strategy,Exit Reason,Mode\n")
        for (t in trades) {
            sb.append("${t.id},")
            sb.append("${t.symbol},")
            sb.append("${t.side.name},")
            sb.append("${String.format(Locale.US, "%.2f", t.volume)},")
            sb.append("${String.format(Locale.US, "%.4f", t.entryPrice)},")
            sb.append("${String.format(Locale.US, "%.4f", t.exitPrice)},")
            sb.append("${t.stopLoss?.let { String.format(Locale.US, "%.4f", it) } ?: ""},")
            sb.append("${t.takeProfit?.let { String.format(Locale.US, "%.4f", it) } ?: ""},")
            sb.append("${String.format(Locale.US, "%.2f", t.profitLoss)},")
            sb.append("${String.format(Locale.US, "%.2f", t.commission)},")
            sb.append("${String.format(Locale.US, "%.2f", t.swap)},")
            sb.append("${String.format(Locale.US, "%.2f", t.netProfitLoss)},")
            sb.append("${String.format(Locale.US, "%.2f", t.rMultiple)},")
            sb.append("${sdf.format(Date(t.openTime))},")
            sb.append("${sdf.format(Date(t.closeTime))},")
            sb.append("${t.durationMillis / 1000},")
            sb.append("${escapeCsv(t.strategyId ?: "")},")
            sb.append("${t.exitReason.name},")
            sb.append("${t.mode}\n")
        }
        return sb.toString()
    }

    fun exportDailyResultsCsv(dailySummaries: List<DailySummary>): String {
        val sb = StringBuilder()
        sb.append("Date,Net PL,Trade Count,Total Lots,Win Rate %\n")
        for (d in dailySummaries) {
            sb.append("${d.fullDate},")
            sb.append("${String.format(Locale.US, "%.2f", d.profitLoss)},")
            sb.append("${d.tradeCount},")
            sb.append("${String.format(Locale.US, "%.2f", d.totalLots)},")
            sb.append("${String.format(Locale.US, "%.1f%%", d.winRatePct)}\n")
        }
        return sb.toString()
    }

    fun exportEquityPointsCsv(points: List<EquityPoint>): String {
        val sb = StringBuilder()
        sb.append("Timestamp,Datetime,Balance,Equity,Drawdown $,Drawdown %\n")
        for (p in points) {
            sb.append("${p.timestamp},")
            sb.append("${sdf.format(Date(p.timestamp))},")
            sb.append("${String.format(Locale.US, "%.2f", p.balance)},")
            sb.append("${String.format(Locale.US, "%.2f", p.equity)},")
            sb.append("${String.format(Locale.US, "%.2f", p.drawdown)},")
            sb.append("${String.format(Locale.US, "%.2f%%", p.drawdownPercentage)}\n")
        }
        return sb.toString()
    }

    fun exportCompleteJson(
        metrics: PerformanceMetrics,
        trades: List<TradeJournalEntry>,
        dailySummaries: List<DailySummary>,
        points: List<EquityPoint>,
        strategyName: String = "N/A",
        symbol: String = "XAUUSD",
        timeframe: String = "M15"
    ): String {
        val sb = StringBuilder()
        sb.append("{\n")
        sb.append("  \"strategy\": \"${escapeJson(strategyName)}\",\n")
        sb.append("  \"symbol\": \"$symbol\",\n")
        sb.append("  \"timeframe\": \"$timeframe\",\n")
        sb.append("  \"generatedAt\": ${System.currentTimeMillis()},\n")
        sb.append("  \"summary\": {\n")
        sb.append("    \"initialBalance\": ${safeJsonNumber(metrics.initialBalance)},\n")
        sb.append("    \"finalBalance\": ${safeJsonNumber(metrics.finalBalance)},\n")
        sb.append("    \"netProfit\": ${safeJsonNumber(metrics.netProfit)},\n")
        sb.append("    \"returnPct\": ${safeJsonNumber(metrics.returnPct)},\n")
        sb.append("    \"grossProfit\": ${safeJsonNumber(metrics.grossProfit)},\n")
        sb.append("    \"grossLoss\": ${safeJsonNumber(metrics.grossLoss)},\n")
        sb.append("    \"profitFactor\": ${safeJsonNumber(metrics.profitFactor)},\n")
        sb.append("    \"winRatePct\": ${safeJsonNumber(metrics.winRatePct)},\n")
        sb.append("    \"totalTrades\": ${metrics.totalTrades},\n")
        sb.append("    \"winningTrades\": ${metrics.winningTrades},\n")
        sb.append("    \"losingTrades\": ${metrics.losingTrades},\n")
        sb.append("    \"expectancy\": ${safeJsonNumber(metrics.expectancy)},\n")
        sb.append("    \"maxDrawdown\": ${safeJsonNumber(metrics.maxDrawdown)},\n")
        sb.append("    \"maxDrawdownPct\": ${safeJsonNumber(metrics.maxDrawdownPct)},\n")
        sb.append("    \"sharpeRatio\": ${safeJsonNumber(metrics.sharpeRatio)},\n")
        sb.append("    \"sortinoRatio\": ${safeJsonNumber(metrics.sortinoRatio)},\n")
        sb.append("    \"recoveryFactor\": ${safeJsonNumber(metrics.recoveryFactor)}\n")
        sb.append("  },\n")
        sb.append("  \"tradesCount\": ${trades.size},\n")
        sb.append("  \"dailySummariesCount\": ${dailySummaries.size},\n")
        sb.append("  \"equityPointsCount\": ${points.size}\n")
        sb.append("}\n")
        return sb.toString()
    }

    private fun safeJsonNumber(v: Double?): String {
        if (v == null || v.isNaN() || v.isInfinite()) return "null"
        return v.toString()
    }

    private fun escapeCsv(str: String): String {
        return if (str.contains(",") || str.contains("\"") || str.contains("\n")) {
            "\"${str.replace("\"", "\"\"")}\""
        } else {
            str
        }
    }

    private fun escapeJson(str: String): String {
        return str.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
    }
}
