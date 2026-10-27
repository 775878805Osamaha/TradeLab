package com.example.core.model

import java.util.Locale

enum class AccountMode {
    LIVE_PAPER,
    REPLAY,
    BACKTEST
}

data class VirtualAccount(
    val id: Long = 0,
    val name: String,
    val initialBalance: Double = 50.0,
    val balance: Double = 50.0,
    val equity: Double = 50.0,
    val margin: Double = 0.0,
    val freeMargin: Double = 50.0,
    val marginLevel: Double = 0.0, // (Equity / Margin) * 100
    val leverage: Double = 100.0,
    val floatingPnL: Double = 0.0,
    val realizedPnL: Double = 0.0,
    val commission: Double = 0.0,
    val swap: Double = 0.0,
    val currency: String = "USD",
    val mode: AccountMode = AccountMode.LIVE_PAPER,
    val isSelected: Boolean = false,
    val createdAt: Long = System.currentTimeMillis()
) : java.io.Serializable {
    val usedMargin: Double get() = margin

    val marginLevelFormatted: String
        get() = if (margin > 0.0) String.format(Locale.US, "%.1f%%", marginLevel) else "N/A"

    companion object {
        fun computeEquity(balance: Double, unrealizedPl: Double, floatingCosts: Double = 0.0): Double {
            return balance + unrealizedPl - floatingCosts
        }

        fun computeFreeMargin(equity: Double, usedMargin: Double): Double {
            return (equity - usedMargin).coerceAtLeast(0.0)
        }

        fun computeMarginLevel(equity: Double, usedMargin: Double): Double {
            return if (usedMargin > 0.0) {
                (equity / usedMargin) * 100.0
            } else {
                0.0
            }
        }
    }
}
