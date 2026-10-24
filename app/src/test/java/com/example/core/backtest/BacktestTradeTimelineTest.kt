package com.example.core.backtest

import com.example.core.model.ExitReason
import com.example.core.model.PositionSide
import com.example.core.model.TradeJournalEntry
import org.junit.Assert.*
import org.junit.Test

class BacktestTradeTimelineTest {
    private fun trade() = TradeJournalEntry(
        accountId = 1,
        symbol = "XAUUSD",
        side = PositionSide.BUY,
        volume = 0.01,
        entryPrice = 2000.0,
        exitPrice = 2001.0,
        profitLoss = 1.0,
        openTime = 200,
        closeTime = 400,
        exitReason = ExitReason.MANUAL_CLOSE,
        mode = "BACKTEST"
    )

    @Test fun acceptsValidHistoricalTrade() {
        BacktestTradeTimeline.validate(listOf(trade()), "XAUUSD", 100, 500)
    }

    @Test fun rejectsWrongInstrument() {
        rejects { BacktestTradeTimeline.validate(listOf(trade().copy(symbol = "EURUSD")), "XAUUSD", 100, 500) }
    }

    @Test fun rejectsFutureExit() {
        rejects { BacktestTradeTimeline.validate(listOf(trade().copy(closeTime = 501)), "XAUUSD", 100, 500) }
    }

    @Test fun rejectsEntryBeforeHistoricalData() {
        rejects { BacktestTradeTimeline.validate(listOf(trade().copy(openTime = 99)), "XAUUSD", 100, 500) }
    }

    @Test fun rejectsNonBacktestProvenance() {
        rejects { BacktestTradeTimeline.validate(listOf(trade().copy(mode = "LIVE_PAPER")), "XAUUSD", 100, 500) }
    }

    @Test fun rejectsReversedTradeTimes() {
        rejects { BacktestTradeTimeline.validate(listOf(trade().copy(openTime = 450)), "XAUUSD", 100, 500) }
    }

    private fun rejects(block: () -> Unit) {
        try { block(); fail("Expected invalid historical trade to be rejected") }
        catch (_: IllegalArgumentException) {}
    }
}
