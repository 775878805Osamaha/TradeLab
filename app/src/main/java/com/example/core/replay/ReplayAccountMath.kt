package com.example.core.replay

import com.example.core.model.Position

/**
 * Financial invariants for the isolated historical replay account.
 * Balance includes realized P&L; equity additionally includes floating P&L.
 */
object ReplayAccountMath {
    fun markToMarket(position: Position, tick: com.example.core.model.Tick): Position {
        require(position.symbol==tick.symbol && tick.bid.isFinite() && tick.ask.isFinite() && tick.bid>0 && tick.ask>=tick.bid)
        val price=if(position.side==com.example.core.model.PositionSide.BUY)tick.bid else tick.ask
        val move=if(position.side==com.example.core.model.PositionSide.BUY)price-position.entryPrice else position.entryPrice-price
        val pnl=move*position.volume*com.example.core.market.DefaultSymbols.getSymbol(position.symbol).contractSize
        require(pnl.isFinite())
        return position.copy(currentPrice=price,profitLoss=pnl)
    }

    fun equity(balance: Double, openPositions: List<Position>): Double {
        require(balance.isFinite()) { "Replay balance must be finite" }
        val floating = openPositions.sumOf { position ->
            require(position.profitLoss.isFinite()) { "Replay floating P&L must be finite" }
            require(position.commission.isFinite() && position.swap.isFinite()) { "Replay costs must be finite" }
            position.netProfitLoss
        }
        val result = balance + floating
        require(result.isFinite()) { "Replay equity overflow" }
        return result
    }

    /**
     * Margin is collateral, not an expense. Validate every position so
     * corrupt or negative margin cannot create fictitious free funds.
     */
    fun usedMargin(openPositions: List<Position>): Double {
        val result = openPositions.sumOf { position ->
            require(position.margin.isFinite() && position.margin >= 0.0) {
                "Replay position margin must be finite and nonnegative"
            }
            position.margin
        }
        require(result.isFinite()) { "Replay margin overflow" }
        return result
    }

    fun freeMargin(balance: Double, openPositions: List<Position>): Double {
        val currentEquity = equity(balance, openPositions)
        val collateral = usedMargin(openPositions)
        // For a negative-equity account, subtraction may overflow to -Infinity.
        // Free margin is still exactly zero in that case. Never let a positive
        // overflow silently inflate available trading funds.
        if (currentEquity <= collateral) return 0.0
        val result = currentEquity - collateral
        require(result.isFinite()) { "Replay free margin overflow" }
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
