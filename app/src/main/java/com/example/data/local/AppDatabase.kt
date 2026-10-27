package com.example.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.example.data.local.dao.*
import com.example.data.local.entity.*

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        AccountEntity::class,
        TrainingCheckpointEntity::class, TrainingExecutionEntity::class,
        SymbolEntity::class,
        CandleEntity::class,
        TickEntity::class,
        OrderEntity::class,
        PositionEntity::class,
        TradeEntity::class,
        StrategyEntity::class,
        BacktestRunEntity::class,
        DrawingEntity::class,
        IndicatorConfigEntity::class,
        ReplaySessionEntity::class
    ],
    version = 3,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun trainingDao(): TrainingDao
    abstract fun accountDao(): AccountDao
    abstract fun symbolDao(): SymbolDao
    abstract fun candleDao(): CandleDao
    abstract fun orderDao(): OrderDao
    abstract fun positionDao(): PositionDao
    abstract fun tradeDao(): TradeDao
    abstract fun strategyDao(): StrategyDao
    abstract fun backtestDao(): BacktestDao
    abstract fun drawingDao(): DrawingDao
    abstract fun indicatorConfigDao(): IndicatorConfigDao
    abstract fun replaySessionDao(): ReplaySessionDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE INDEX IF NOT EXISTS index_trades_openTime ON trades (openTime)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_trades_closeTime ON trades (closeTime)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_trades_mode ON trades (mode)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_backtest_runs_symbol ON backtest_runs (symbol)")
            }
        }

        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE TABLE IF NOT EXISTS training_checkpoints (id INTEGER NOT NULL, payload BLOB NOT NULL, initialAmount TEXT NOT NULL, balanceAmount TEXT NOT NULL, fundedAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL, PRIMARY KEY(id))")
                db.execSQL("CREATE TABLE IF NOT EXISTS training_executions (checkpointId INTEGER NOT NULL, ordinal INTEGER NOT NULL, symbol TEXT NOT NULL, marketCloseTime INTEGER NOT NULL, recordedAt INTEGER NOT NULL, netAmount TEXT NOT NULL, commissionAmount TEXT NOT NULL, volume TEXT NOT NULL, PRIMARY KEY(checkpointId, ordinal))")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_training_executions_checkpointId ON training_executions(checkpointId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_training_executions_recordedAt ON training_executions(recordedAt)")
            }
        }

        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "tradelab_database.db"
                )
                    .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
