package com.example.core.replay

import com.example.core.model.Position

/**
 * Financial invariants for the isolated historical replay account.
 * Balance includes realized P&L; equity additionally includes floating P&L.
 */
object ReplayAccountMath {
    fun equity(balance: Double, openPositions: List<Position>): Double {
        require(balance.isFinite()) { "Replay balance must be finite" }
        val floating = openPositions.sumOf { position ->
            require(position.profitLoss.isFinite()) { "Replay floating P&L must be finite" }
            position.profitLoss
        }
        val result = balance + floating
        require(result.isFinite()) { "Replay equity overflow" }
        return result
    }

    fun realizedBalance(balance: Double, realizedNetProfitLoss: Double): Double {
        require(balance.isFinite() && realizedNetProfitLoss.isFinite()) {
            "Replay realized P&L must be finite"
        }
        val result = balance + realizedNetProfitLoss
        require(result.isFinite()) { "Replay balance overflow" }
        return result
    }
}
