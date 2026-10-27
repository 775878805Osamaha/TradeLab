package com.example.core.model

/** Read-only training report; never enters the live-paper execution account. */
data class ReplayReport(
    val account: VirtualAccount,
    val positions: List<Position>,
    val orders: List<Order>,
    val trades: List<TradeJournalEntry>,
    val curve: List<EquityPoint> = emptyList(),
    val maxDrawdown: Double = 0.0,
    val maxDrawdownPercent: Double = 0.0
)
