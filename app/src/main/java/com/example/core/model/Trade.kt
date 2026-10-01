package com.example.core.model

enum class ExitReason {
    TAKE_PROFIT,
    STOP_LOSS,
    MANUAL_CLOSE,
    STRATEGY_CLOSE,
    TRAILING_STOP,
    BREAK_EVEN
}

data class TradeJournalEntry(
    val id: Long = 0,
    val accountId: Long,
    val symbol: String,
    val side: PositionSide,
    val volume: Double,
    val entryPrice: Double,
    val exitPrice: Double,
    val stopLoss: Double? = null,
    val takeProfit: Double? = null,
    val profitLoss: Double,
    val commission: Double = 0.0,
    val swap: Double = 0.0,
    val netProfitLoss: Double = profitLoss - commission - swap,
    val openTime: Long,
    val closeTime: Long,
    val strategyId: String? = null,
    val exitReason: ExitReason,
    val rMultiple: Double = 0.0,
    val notes: String = "",
    val mode: String = "LIVE_PAPER"
) {
    val durationMillis: Long get() = closeTime - openTime
    val isWin: Boolean get() = netProfitLoss > 0.0
}
