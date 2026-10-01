package com.example.core.challenge

import com.example.core.model.ChallengeConfig
import com.example.core.model.ChallengeStatus
import com.example.core.model.TradeJournalEntry
import com.example.core.model.VirtualAccount
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.max
import kotlin.math.min

object FtmoChallengeEvaluator {

    fun evaluate(
        account: VirtualAccount,
        trades: List<TradeJournalEntry>,
        config: ChallengeConfig
    ): ChallengeStatus {
        val violations = mutableListOf<String>()

        val maxAllowedDailyLoss = account.initialBalance * (config.maxDailyLossPct / 100.0)
        val maxAllowedOverallLoss = account.initialBalance * (config.maxOverallLossPct / 100.0)
        val targetProfit = account.initialBalance * (config.profitTargetPct / 100.0)

        // Group trades by date to calculate daily P/L and trading days
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val tradesByDate = trades.groupBy { sdf.format(Date(it.closeTime)) }
        val tradingDaysCount = tradesByDate.keys.size

        // Calculate today's P/L
        val todayStr = sdf.format(Date())
        val todayTrades = tradesByDate[todayStr] ?: emptyList()
        val dailyProfitLoss = todayTrades.sumOf { it.netProfitLoss }

        // Check daily loss violations across all recorded trading days
        var worstDayLoss = 0.0
        for ((date, dayTrades) in tradesByDate) {
            val dayPl = dayTrades.sumOf { it.netProfitLoss }
            if (dayPl < 0 && -dayPl > worstDayLoss) {
                worstDayLoss = -dayPl
            }
            if (dayPl < 0 && -dayPl > maxAllowedDailyLoss) {
                violations.add("تجاوز حد الخسارة اليومي في تاريخ $date بمبلغ $${String.format("%.2f", -dayPl)}")
            }
        }

        // Check overall max loss from initial balance or peak
        val currentLoss = account.initialBalance - account.equity
        val isDailyLossBreached = worstDayLoss > maxAllowedDailyLoss
        val isMaxLossBreached = currentLoss > maxAllowedOverallLoss
        if (isMaxLossBreached) {
            violations.add("تجاوز الحد الأقصى للتراجع الكلي: خسارة $${String.format("%.2f", currentLoss)}")
        }

        val remainingDailyLoss = max(0.0, maxAllowedDailyLoss - worstDayLoss)
        val remainingMaxLoss = max(0.0, maxAllowedOverallLoss - currentLoss)

        val totalNetProfit = account.equity - account.initialBalance
        val profitTargetProgress = if (targetProfit > 0) {
            (totalNetProfit / targetProfit * 100.0).coerceIn(0.0, 100.0)
        } else 0.0

        val isTargetReached = totalNetProfit >= targetProfit && tradingDaysCount >= config.minTradingDays

        // Calculate Discipline Score (100 base, penalized for rule infractions & excessive risks)
        var score = 100
        if (isDailyLossBreached) score -= 40
        if (isMaxLossBreached) score -= 40
        if (violations.isNotEmpty()) score -= (violations.size * 10)

        // Penalty for trades without SL
        val tradesWithoutSl = trades.count { it.stopLoss == null }
        if (tradesWithoutSl > 0) {
            score -= min(25, tradesWithoutSl * 5)
        }

        val finalScore = score.coerceIn(0, 100)

        return ChallengeStatus(
            disciplineScore = finalScore,
            currentBalance = account.balance,
            currentEquity = account.equity,
            dailyProfitLoss = dailyProfitLoss,
            remainingDailyLoss = remainingDailyLoss,
            remainingMaxLoss = remainingMaxLoss,
            profitTargetProgressPct = profitTargetProgress,
            tradingDaysCount = tradingDaysCount,
            isDailyLossBreached = isDailyLossBreached,
            isMaxLossBreached = isMaxLossBreached,
            isTargetReached = isTargetReached,
            ruleViolations = violations
        )
    }
}
