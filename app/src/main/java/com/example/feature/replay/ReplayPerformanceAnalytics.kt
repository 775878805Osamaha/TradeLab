package com.example.feature.replay

import com.example.core.model.TradeJournalEntry
import java.util.Locale
import kotlin.math.max

/**
 * Pure deterministic analytics: no wall-clock reads, network requests or future candles.
 * Inputs must be limited to the revealed Replay session.
 */
data class ReplayPerformanceReport(
    val closedCount: Int,
    val wins: Int,
    val losses: Int,
    val breakeven: Int,
    val netProfit: Double,
    val grossProfit: Double,
    val grossLoss: Double,
    val winRatePercent: Double,
    val profitFactor: Double?,
    val averageTrade: Double,
    val averageWin: Double,
    val averageLoss: Double,
    val payoffRatio: Double?,
    val expectancy: Double,
    val longestWinStreak: Int,
    val longestLossStreak: Int,
    val maxEquityDrawdownPercent: Double,
    val maxEquityDrawdownAmount: Double,
    val peakEquity: Double,
    val currentDrawdownPercent: Double,
    val equityReturnPercent: Double,
    val sampledBars: Int
)

object ReplayPerformanceAnalytics {
    fun calculate(
        trades: List<TradeJournalEntry>,
        samples: List<ReplayEquitySample>,
        initialBalance: Double,
        currentEquity: Double
    ): ReplayPerformanceReport {
        val realized = trades.map { it.netProfitLoss }.filter { it.isFinite() }
        val wins = realized.count { it > 0.0 }
        val losses = realized.count { it < 0.0 }
        val grossProfit = realized.filter { it > 0.0 }.sum()
        val grossLoss = -realized.filter { it < 0.0 }.sum()
        var longestWins = 0
        var longestLosses = 0
        var currentWins = 0
        var currentLosses = 0
        realized.forEach { pnl ->
            when {
                pnl > 0.0 -> { currentWins++; currentLosses = 0 }
                pnl < 0.0 -> { currentLosses++; currentWins = 0 }
                else -> { currentWins = 0; currentLosses = 0 }
            }
            longestWins = max(longestWins, currentWins)
            longestLosses = max(longestLosses, currentLosses)
        }

        var peak = initialBalance.takeIf { it.isFinite() && it > 0.0 } ?: 0.0
        var maxDrawdown = 0.0
        var maxDrawdownAmount = 0.0
        val ordered = samples.filter { it.equity.isFinite() }.sortedBy { it.candleIndex }
        ordered.forEach { sample ->
            peak = max(peak, sample.equity)
            val amount = max(0.0, peak - sample.equity)
            maxDrawdownAmount = max(maxDrawdownAmount, amount)
            if (peak > 0.0) maxDrawdown = max(maxDrawdown, 100.0 * amount / peak)
        }
        val equity = currentEquity.takeIf { it.isFinite() } ?: initialBalance
        peak = max(peak, equity)
        val currentDrawdown = if (peak > 0.0) max(0.0, peak - equity) * 100.0 / peak else 0.0
        val averageWin = if (wins > 0) grossProfit / wins else 0.0
        val averageLoss = if (losses > 0) grossLoss / losses else 0.0
        return ReplayPerformanceReport(
            closedCount = realized.size,
            wins = wins,
            losses = losses,
            breakeven = realized.size - wins - losses,
            netProfit = realized.sum(),
            grossProfit = grossProfit,
            grossLoss = grossLoss,
            winRatePercent = if (realized.isEmpty()) 0.0 else wins * 100.0 / realized.size,
            profitFactor = if (grossLoss > 0.0) grossProfit / grossLoss else null,
            averageTrade = if (realized.isEmpty()) 0.0 else realized.average(),
            averageWin = averageWin,
            averageLoss = averageLoss,
            payoffRatio = if (averageLoss > 0.0) averageWin / averageLoss else null,
            expectancy = if (realized.isEmpty()) 0.0 else realized.average(),
            longestWinStreak = longestWins,
            longestLossStreak = longestLosses,
            maxEquityDrawdownPercent = maxDrawdown,
            maxEquityDrawdownAmount = maxDrawdownAmount,
            peakEquity = peak,
            currentDrawdownPercent = currentDrawdown,
            equityReturnPercent = if (initialBalance > 0.0 && initialBalance.isFinite())
                (equity - initialBalance) * 100.0 / initialBalance else 0.0,
            sampledBars = ordered.size
        )
    }

    /** Trade order is the order of closure in the revealed Replay timeline. */
    fun exportTradesCsv(trades: List<TradeJournalEntry>): String = buildString {
        appendLine("closed_trade_number,net_profit_loss_usd")
        trades.forEachIndexed { index, trade ->
            if (trade.netProfitLoss.isFinite()) {
                append(index + 1)
                append(',')
                appendLine(String.format(Locale.US, "%.6f", trade.netProfitLoss))
            }
        }
    }

    /** Stable spreadsheet-ready output with fixed US decimal separator. */
    fun exportEquityCsv(samples: List<ReplayEquitySample>): String = buildString {
        appendLine("candle_index,balance_usd,equity_usd")
        samples.sortedBy { it.candleIndex }.forEach {
            if (it.balance.isFinite() && it.equity.isFinite()) {
                append(it.candleIndex)
                append(',')
                append(String.format(Locale.US, "%.6f", it.balance))
                append(',')
                appendLine(String.format(Locale.US, "%.6f", it.equity))
            }
        }
    }
}
