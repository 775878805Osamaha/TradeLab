package com.example.core.backtest

import com.example.core.model.TradeJournalEntry

/** Enforces historical trade provenance and chronological execution boundaries. */
object BacktestTradeTimeline {
    fun validate(
        trades: List<TradeJournalEntry>,
        symbol: String,
        firstBarOpen: Long,
        lastBarClose: Long
    ) {
        require(symbol.isNotBlank()) { "Backtest symbol must not be blank" }
        require(firstBarOpen >= 0L && lastBarClose > firstBarOpen) {
            "Invalid historical execution window"
        }
        trades.forEachIndexed { index, trade ->
            require(trade.symbol.equals(symbol, ignoreCase = true)) {
                "Trade $index belongs to another symbol"
            }
            require(trade.openTime in firstBarOpen..lastBarClose) {
                "Trade $index opened outside historical window"
            }
            require(trade.closeTime in trade.openTime..lastBarClose) {
                "Trade $index closed outside historical window"
            }
            require(trade.mode == "BACKTEST") {
                "Trade $index has invalid execution provenance"
            }
        }
    }
}
