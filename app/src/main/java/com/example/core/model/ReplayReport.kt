package com.example.core.model

/** Read-only training report; never enters the live-paper execution account. */
data class ReplayReport(
    val account: VirtualAccount,
    val positions: List<Position>,
    val orders: List<Order>,
    val trades: List<TradeJournalEntry>
)
