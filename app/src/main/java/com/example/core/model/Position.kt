package com.example.core.model

import java.util.Locale
import kotlin.math.abs

enum class PositionSide(val displayNameAr: String) {
    BUY("شراء"),
    SELL("بيع")
}

data class Position(
    val id: Long = 0,
    val accountId: Long,
    val symbol: String,
    val side: PositionSide,
    val volume: Double,
    val entryPrice: Double,
    val currentPrice: Double,
    val stopLoss: Double? = null,
    val takeProfit: Double? = null,
    val openTime: Long = System.currentTimeMillis(),
    val profitLoss: Double = 0.0,
    val swap: Double = 0.0,
    val commission: Double = 0.0,
    val margin: Double = 0.0,
    val strategyId: String? = null,
    val mode: String = "LIVE_PAPER",
    val trailingStopDistance: Double? = null,
    val isBreakEven: Boolean = false
) : java.io.Serializable {
    val netProfitLoss: Double get() = profitLoss - commission - swap

    val pnlPercent: Double
        get() = if (margin > 0.0) (netProfitLoss / margin) * 100.0 else 0.0

    val riskAmount: Double
        get() = if (stopLoss != null) abs(entryPrice - stopLoss) * volume * 100.0 else 0.0

    val rMultiple: Double
        get() = if (stopLoss != null) {
            val riskPerUnit = abs(entryPrice - stopLoss)
            if (riskPerUnit > 0.0) {
                val gain = if (side == PositionSide.BUY) (currentPrice - entryPrice) else (entryPrice - currentPrice)
                gain / riskPerUnit
            } else 0.0
        } else 0.0

    val durationMillis: Long
        get() = (System.currentTimeMillis() - openTime).coerceAtLeast(0L)

    val durationFormatted: String
        get() {
            val seconds = durationMillis / 1000
            val minutes = seconds / 60
            val hours = minutes / 60
            val days = hours / 24
            return when {
                days > 0 -> "${days}d ${hours % 24}h"
                hours > 0 -> "${hours}h ${minutes % 60}m"
                minutes > 0 -> "${minutes}m ${seconds % 60}s"
                else -> "${seconds}s"
            }
        }
}

data class ModifyPositionRequest(
    val positionId: Long,
    val stopLoss: Double?,
    val takeProfit: Double?,
    val trailingStopDistance: Double? = null
)
