package com.example.data.local.dao

import androidx.room.*
import com.example.data.local.entity.*
import kotlinx.coroutines.flow.Flow

@Dao
interface AccountDao {
    @Query("SELECT * FROM accounts ORDER BY createdAt ASC")
    fun getAllAccounts(): Flow<List<AccountEntity>>

    @Query("SELECT * FROM accounts WHERE id = :id LIMIT 1")
    suspend fun getAccountById(id: Long): AccountEntity?

    @Query("SELECT * FROM accounts WHERE isSelected = 1 LIMIT 1")
    fun getSelectedAccountFlow(): Flow<AccountEntity?>

    @Query("SELECT * FROM accounts WHERE isSelected = 1 LIMIT 1")
    suspend fun getSelectedAccount(): AccountEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAccount(account: AccountEntity): Long

    @Update
    suspend fun updateAccount(account: AccountEntity)

    @Query("UPDATE accounts SET isSelected = 0")
    suspend fun clearSelection()

    @Query("UPDATE accounts SET isSelected = 1 WHERE id = :id")
    suspend fun selectAccount(id: Long)

    @Query("DELETE FROM accounts WHERE id = :id")
    suspend fun deleteAccountById(id: Long)

    @Query("DELETE FROM accounts")
    suspend fun deleteAllAccounts()
}

@Dao
interface SymbolDao {
    @Query("SELECT * FROM symbols ORDER BY isFavorite DESC, symbol ASC")
    fun getAllSymbols(): Flow<List<SymbolEntity>>

    @Query("SELECT * FROM symbols WHERE symbol = :symbol LIMIT 1")
    suspend fun getSymbol(symbol: String): SymbolEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSymbols(symbols: List<SymbolEntity>)

    @Query("UPDATE symbols SET isFavorite = :isFavorite WHERE symbol = :symbol")
    suspend fun updateFavorite(symbol: String, isFavorite: Boolean)
}

@Dao
interface CandleDao {
    @Query("SELECT * FROM candles WHERE symbol = :symbol AND timeframe = :timeframe ORDER BY openTime ASC")
    fun getCandlesFlow(symbol: String, timeframe: String): Flow<List<CandleEntity>>

    @Query("SELECT * FROM candles WHERE symbol = :symbol AND timeframe = :timeframe AND openTime <= :untilTime ORDER BY openTime ASC")
    suspend fun getCandlesUntil(symbol: String, timeframe: String, untilTime: Long): List<CandleEntity>

    @Query("SELECT * FROM candles WHERE symbol = :symbol AND timeframe = :timeframe AND openTime BETWEEN :fromTime AND :toTime ORDER BY openTime ASC")
    suspend fun getCandlesRange(symbol: String, timeframe: String, fromTime: Long, toTime: Long): List<CandleEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertCandles(candles: List<CandleEntity>)

    @Query("DELETE FROM candles WHERE symbol = :symbol AND timeframe = :timeframe")
    suspend fun deleteCandles(symbol: String, timeframe: String)
}

@Dao
interface OrderDao {
    @Query("SELECT * FROM orders WHERE accountId = :accountId ORDER BY createdAt DESC")
    fun getOrdersForAccount(accountId: Long): Flow<List<OrderEntity>>

    @Query("SELECT * FROM orders WHERE accountId = :accountId AND status = 'PENDING'")
    suspend fun getPendingOrders(accountId: Long): List<OrderEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertOrder(order: OrderEntity): Long

    @Update
    suspend fun updateOrder(order: OrderEntity)

    @Query("DELETE FROM orders WHERE id = :orderId")
    suspend fun deleteOrder(orderId: Long)

    @Query("DELETE FROM orders WHERE accountId = :accountId")
    suspend fun deleteOrdersForAccount(accountId: Long)
}

@Dao
interface PositionDao {
    @Query("SELECT * FROM positions WHERE accountId = :accountId ORDER BY openTime DESC")
    fun getPositionsForAccount(accountId: Long): Flow<List<PositionEntity>>

    @Query("SELECT * FROM positions WHERE accountId = :accountId")
    suspend fun getPositionsSync(accountId: Long): List<PositionEntity>

    @Query("SELECT * FROM positions WHERE id = :id LIMIT 1")
    suspend fun getPositionById(id: Long): PositionEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPosition(position: PositionEntity): Long

    @Update
    suspend fun updatePosition(position: PositionEntity)

    @Query("DELETE FROM positions WHERE id = :id")
    suspend fun deletePosition(id: Long)

    @Query("DELETE FROM positions WHERE accountId = :accountId")
    suspend fun deletePositionsForAccount(accountId: Long)
}

@Dao
interface TradeDao {
    @Query("SELECT * FROM trades WHERE accountId = :accountId ORDER BY closeTime DESC")
    fun getTradesForAccount(accountId: Long): Flow<List<TradeEntity>>

    @Query("SELECT * FROM trades WHERE accountId = :accountId ORDER BY closeTime DESC")
    suspend fun getTradesSync(accountId: Long): List<TradeEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTrade(trade: TradeEntity): Long

    @Query("DELETE FROM trades WHERE accountId = :accountId")
    suspend fun deleteTradesForAccount(accountId: Long)
}

@Dao
interface StrategyDao {
    @Query("SELECT * FROM strategies")
    fun getAllStrategies(): Flow<List<StrategyEntity>>

    @Query("SELECT * FROM strategies WHERE id = :id LIMIT 1")
    suspend fun getStrategyById(id: String): StrategyEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertStrategy(strategy: StrategyEntity)

    @Update
    suspend fun updateStrategy(strategy: StrategyEntity)
}

@Dao
interface BacktestDao {
    @Query("SELECT * FROM backtest_runs ORDER BY executedAt DESC")
    fun getAllRuns(): Flow<List<BacktestRunEntity>>

    @Query("SELECT * FROM backtest_runs WHERE id = :id LIMIT 1")
    suspend fun getRunById(id: Long): BacktestRunEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertRun(run: BacktestRunEntity): Long

    @Query("DELETE FROM backtest_runs WHERE id = :id")
    suspend fun deleteRun(id: Long)
}

@Dao
interface DrawingDao {
    @Query("SELECT * FROM drawings WHERE symbol = :symbol AND timeframe = :timeframe")
    fun getDrawings(symbol: String, timeframe: String): Flow<List<DrawingEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDrawing(drawing: DrawingEntity): Long

    @Query("DELETE FROM drawings WHERE id = :id")
    suspend fun deleteDrawing(id: Long)

    @Query("DELETE FROM drawings WHERE symbol = :symbol AND timeframe = :timeframe")
    suspend fun clearDrawings(symbol: String, timeframe: String)
}

@Dao
interface IndicatorConfigDao {
    @Query("SELECT * FROM indicator_configs")
    fun getAllConfigs(): Flow<List<IndicatorConfigEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveConfigs(configs: List<IndicatorConfigEntity>)

    @Update
    suspend fun updateConfig(config: IndicatorConfigEntity)
}

@Dao
interface ReplaySessionDao {
    @Query("SELECT * FROM replay_sessions ORDER BY updatedAt DESC")
    fun getAllSessions(): Flow<List<ReplaySessionEntity>>

    @Query("SELECT * FROM replay_sessions WHERE status IN ('READY', 'RUNNING', 'PAUSED') ORDER BY updatedAt DESC LIMIT 1")
    suspend fun getActiveSession(): ReplaySessionEntity?

    @Query("SELECT * FROM replay_sessions WHERE id = :id LIMIT 1")
    suspend fun getSessionById(id: Long): ReplaySessionEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSession(session: ReplaySessionEntity): Long

    @Update
    suspend fun updateSession(session: ReplaySessionEntity)

    @Query("DELETE FROM replay_sessions WHERE id = :id")
    suspend fun deleteSession(id: Long)
}

