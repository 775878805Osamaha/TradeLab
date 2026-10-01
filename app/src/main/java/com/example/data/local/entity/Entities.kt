package com.example.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Index

@Entity(
    tableName = "accounts",
    indices = [Index(value = ["isSelected"])]
)
data class AccountEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val initialBalance: Double,
    val balance: Double,
    val equity: Double,
    val margin: Double,
    val freeMargin: Double,
    val marginLevel: Double,
    val leverage: Double,
    val currency: String,
    val mode: String,
    val isSelected: Boolean,
    val createdAt: Long
)

@Entity(
    tableName = "symbols",
    indices = [Index(value = ["isFavorite"])]
)
data class SymbolEntity(
    @PrimaryKey val symbol: String,
    val name: String,
    val category: String,
    val digits: Int,
    val pipSize: Double,
    val contractSize: Double,
    val minLot: Double,
    val maxLot: Double,
    val lotStep: Double,
    val defaultSpreadPips: Double,
    val isFavorite: Boolean
)

@Entity(
    tableName = "candles",
    indices = [
        Index(value = ["symbol", "timeframe", "openTime"], unique = true),
        Index(value = ["symbol", "timeframe", "openTime", "closeTime"])
    ]
)
data class CandleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val symbol: String,
    val timeframe: String,
    val openTime: Long,
    val closeTime: Long = openTime + 60000L,
    val open: Double,
    val high: Double,
    val low: Double,
    val close: Double,
    val volume: Double,
    val source: String = "MARKET_FEED"
)

@Entity(
    tableName = "ticks",
    indices = [
        Index(value = ["symbol", "timestamp"])
    ]
)
data class TickEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val symbol: String,
    val bid: Double,
    val ask: Double,
    val timestamp: Long,
    val volume: Double
)

@Entity(
    tableName = "orders",
    indices = [
        Index(value = ["accountId", "status"]),
        Index(value = ["symbol"]),
        Index(value = ["createdAt"])
    ]
)
data class OrderEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val accountId: Long,
    val symbol: String,
    val type: String,
    val side: String,
    val volume: Double,
    val requestedPrice: Double,
    val stopLoss: Double?,
    val takeProfit: Double?,
    val status: String,
    val createdAt: Long,
    val executedPrice: Double?,
    val executedAt: Long?,
    val comment: String?
)

@Entity(
    tableName = "positions",
    indices = [
        Index(value = ["accountId"]),
        Index(value = ["symbol"]),
        Index(value = ["openTime"])
    ]
)
data class PositionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val accountId: Long,
    val symbol: String,
    val side: String,
    val volume: Double,
    val entryPrice: Double,
    val currentPrice: Double,
    val stopLoss: Double?,
    val takeProfit: Double?,
    val openTime: Long,
    val profitLoss: Double,
    val swap: Double,
    val commission: Double,
    val margin: Double,
    val strategyId: String?,
    val mode: String,
    val trailingStopDistance: Double?,
    val isBreakEven: Boolean
)

@Entity(
    tableName = "trades",
    indices = [
        Index(value = ["accountId", "closeTime"]),
        Index(value = ["symbol"]),
        Index(value = ["strategyId"]),
        Index(value = ["exitReason"]),
        Index(value = ["openTime"]),
        Index(value = ["closeTime"]),
        Index(value = ["mode"])
    ]
)
data class TradeEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val accountId: Long,
    val symbol: String,
    val side: String,
    val volume: Double,
    val entryPrice: Double,
    val exitPrice: Double,
    val stopLoss: Double?,
    val takeProfit: Double?,
    val profitLoss: Double,
    val commission: Double,
    val swap: Double,
    val openTime: Long,
    val closeTime: Long,
    val strategyId: String?,
    val exitReason: String,
    val rMultiple: Double,
    val notes: String,
    val mode: String
)

@Entity(tableName = "strategies")
data class StrategyEntity(
    @PrimaryKey val id: String,
    val name: String,
    val description: String,
    val symbol: String,
    val timeframe: String,
    val parametersJson: String,
    val riskPct: Double,
    val defaultLot: Double,
    val stopLossPips: Double?,
    val takeProfitPips: Double?,
    val isEnabled: Boolean
)

@Entity(
    tableName = "backtest_runs",
    indices = [
        Index(value = ["strategyId"]),
        Index(value = ["symbol"]),
        Index(value = ["executedAt"])
    ]
)
data class BacktestRunEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val strategyId: String,
    val strategyName: String,
    val symbol: String,
    val timeframe: String,
    val startTime: Long,
    val endTime: Long,
    val initialBalance: Double,
    val finalBalance: Double,
    val netProfit: Double,
    val winRatePct: Double,
    val profitFactor: Double?,
    val maxDrawdownPct: Double,
    val totalTrades: Int,
    val metricsJson: String,
    val equityCurveJson: String,
    val executedAt: Long,
    val winningTrades: Int = 0,
    val losingTrades: Int = 0,
    val maxDrawdown: Double = 0.0,
    val returnPercentage: Double = 0.0,
    val expectancy: Double? = null,
    val status: String = "COMPLETED",
    val startedAt: Long = executedAt,
    val completedAt: Long = executedAt,
    val duration: Long = 0L,
    val errorMessage: String? = null
)

@Entity(
    tableName = "drawings",
    indices = [Index(value = ["symbol", "timeframe"])]
)
data class DrawingEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val symbol: String,
    val timeframe: String,
    val type: String, // HORIZONTAL_LINE, VERTICAL_LINE, TRENDLINE, RECTANGLE, FIBONACCI, MEASUREMENT
    val pointsJson: String, // serialized points
    val colorHex: String,
    val strokeWidth: Float
)

@Entity(tableName = "indicator_configs")
data class IndicatorConfigEntity(
    @PrimaryKey val id: String,
    val name: String,
    val type: String, // SMA, EMA, RSI, MACD, ATR, BOLLINGER, VWAP
    val isEnabled: Boolean,
    val parametersJson: String,
    val colorHex: String
)

@Entity(
    tableName = "replay_sessions",
    indices = [
        Index(value = ["accountId"]),
        Index(value = ["symbol"]),
        Index(value = ["status"])
    ]
)
data class ReplaySessionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val accountId: Long,
    val symbol: String,
    val timeframe: String,
    val startDateTime: Long,
    val currentDateTime: Long,
    val endDateTime: Long,
    val initialBalance: Double,
    val status: String,
    val speed: Float,
    val currentCandleIndex: Int,
    val createdAt: Long,
    val updatedAt: Long
)

