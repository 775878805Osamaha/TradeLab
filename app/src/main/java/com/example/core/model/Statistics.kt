package com.example.core.model

data class PerformanceMetrics(
    val initialBalance: Double,
    val finalBalance: Double,
    val equity: Double,
    val netProfit: Double,
    val returnPct: Double,
    val grossProfit: Double,
    val grossLoss: Double,
    val profitFactor: Double?,
    val winRatePct: Double,
    val totalTrades: Int,
    val winningTrades: Int,
    val losingTrades: Int,
    val avgWin: Double?,
    val avgLoss: Double?,
    val expectancy: Double?,
    val maxDrawdown: Double,
    val maxDrawdownPct: Double,
    val maxConsecutiveWins: Int,
    val maxConsecutiveLosses: Int,
    val bestTrade: Double?,
    val worstTrade: Double?,
    val avgDurationMillis: Long,
    val totalVolume: Double,
    val avgRMultiple: Double?,
    val sharpeRatio: Double?,
    val sortinoRatio: Double?,
    val recoveryFactor: Double?,
    val shortestDurationMillis: Long = 0L,
    val longestDurationMillis: Long = 0L,
    val avgVolume: Double = if (totalTrades > 0) totalVolume / totalTrades else 0.0,
    val largestVolume: Double = 0.0,
    val smallestVolume: Double = 0.0,
    val avgRiskAmount: Double? = null,
    val avgRiskPct: Double? = null,
    val bestTradeRecord: TradeJournalEntry? = null,
    val worstTradeRecord: TradeJournalEntry? = null
)

data class EquityPoint(
    val timestamp: Long,
    val balance: Double,
    val equity: Double,
    val drawdown: Double,
    val highWatermark: Double
) {
    val drawdownPercentage: Double
        get() = if (highWatermark > 0.0) (drawdown / highWatermark) * 100.0 else 0.0
}

data class DailySummary(
    val dateStr: String, // e.g. "30/09"
    val fullDate: String, // "2026-09-30"
    val profitLoss: Double,
    val tradeCount: Int,
    val totalLots: Double,
    val winRatePct: Double
)
