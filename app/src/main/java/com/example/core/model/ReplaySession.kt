package com.example.core.model

enum class ReplayStatus {
    READY,
    RUNNING,
    PAUSED,
    COMPLETED,
    CANCELLED
}

data class ReplaySession(
    val id: Long = 0,
    val accountId: Long,
    val symbol: String,
    val timeframe: Timeframe,
    val startDateTime: Long,
    val currentDateTime: Long,
    val endDateTime: Long,
    val initialBalance: Double = 50.0,
    val status: ReplayStatus = ReplayStatus.READY,
    val speed: Float = 1.0f,
    val currentCandleIndex: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)

data class ReplayCheckpoint(
    val sessionId: Long,
    val candleIndex: Int,
    val timestamp: Long,
    val balance: Double,
    val equity: Double,
    val openPositions: List<Position>,
    val closedTradesCount: Int
)
