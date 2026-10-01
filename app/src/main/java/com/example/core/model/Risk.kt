package com.example.core.model

data class RiskAnalysis(
    val suggestedLotSize: Double,
    val requiredMargin: Double,
    val freeMarginRemaining: Double,
    val marginLevelAfterOrder: Double,
    val potentialLoss: Double,
    val potentialProfit: Double,
    val isMarginSufficient: Boolean,
    val riskAmount: Double = potentialLoss,
    val riskPercentage: Double = 0.0,
    val riskRewardRatio: Double? = null,
    val errorMessage: String? = null
)

data class ChallengeConfig(
    val accountSize: Double = 50.0,
    val profitTargetPct: Double = 10.0,
    val maxDailyLossPct: Double = 5.0,
    val maxOverallLossPct: Double = 10.0,
    val minTradingDays: Int = 4,
    val maxTradingDays: Int = 30
)

data class ChallengeStatus(
    val disciplineScore: Int, // 0 - 100 based on user configured rules & actual behavior
    val currentBalance: Double,
    val currentEquity: Double,
    val dailyProfitLoss: Double,
    val remainingDailyLoss: Double,
    val remainingMaxLoss: Double,
    val profitTargetProgressPct: Double,
    val tradingDaysCount: Int,
    val isDailyLossBreached: Boolean,
    val isMaxLossBreached: Boolean,
    val isTargetReached: Boolean,
    val ruleViolations: List<String>
)
