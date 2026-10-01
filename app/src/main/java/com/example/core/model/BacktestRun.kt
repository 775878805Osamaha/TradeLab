package com.example.core.model

enum class BacktestRunStatus {
    QUEUED,
    RUNNING,
    COMPLETED,
    CANCELLED,
    FAILED
}

enum class PositionSizingMode(val displayNameAr: String) {
    FIXED_LOT("حجم عقد ثابت (Fixed Lot)"),
    RISK_PERCENTAGE("نسبة مخاطرة مئوية % (Risk %)"),
    FIXED_MONETARY_RISK("مبلغ مخاطرة نقدي محدد ($)")
}

data class BacktestRun(
    val id: Long = 0,
    val strategyId: String,
    val strategyName: String,
    val symbol: String,
    val timeframe: Timeframe,
    val startTime: Long,
    val endTime: Long,
    val initialBalance: Double,
    val finalBalance: Double,
    val netProfit: Double,
    val returnPercentage: Double,
    val totalTrades: Int,
    val winningTrades: Int,
    val losingTrades: Int,
    val maxDrawdown: Double,
    val maxDrawdownPercentage: Double,
    val profitFactor: Double?,
    val winRate: Double,
    val expectancy: Double?,
    val status: BacktestRunStatus = BacktestRunStatus.COMPLETED,
    val startedAt: Long = System.currentTimeMillis(),
    val completedAt: Long = System.currentTimeMillis(),
    val duration: Long = (completedAt - startedAt).coerceAtLeast(0L),
    val errorMessage: String? = null
)
