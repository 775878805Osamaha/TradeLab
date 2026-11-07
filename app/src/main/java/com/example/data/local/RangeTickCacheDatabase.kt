package com.example.data.local

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/**
 * Separate from the personal/trading ledger. Adding a disk cache never
 * migrates or risks deleting the user's existing accounts and trades.
 */
@Entity(
    tableName = "verified_ctrader_bid_slices",
    primaryKeys = ["source", "symbol", "fromMillis", "toMillis"],
    indices = [Index(value = ["source", "symbol", "toMillis"])]
)
data class RangeTickSliceEntity(
    val source: String,
    val symbol: String,
    val fromMillis: Long,
    val toMillis: Long,
    val quoteCount: Int,
    val compressedBidQuotes: ByteArray,
    val savedAtMillis: Long
)

data class RangeTickDiskSpan(val fromMillis: Long, val toMillis: Long)

/** Precomputed bars for an exact verified tick window, never partial pages. */
@Entity(
    tableName = "verified_ctrader_range_snapshots",
    primaryKeys = ["source", "symbol", "fromMillis", "toMillis", "rangeTicks", "tickSizeBits", "includeIncomplete"],
    indices = [Index(value = ["source", "symbol", "rangeTicks", "toMillis"])]
)
data class RangeBarSnapshotEntity(
    val source: String,
    val symbol: String,
    val fromMillis: Long,
    val toMillis: Long,
    val rangeTicks: Int,
    val tickSizeBits: Long,
    val includeIncomplete: Boolean,
    val compressedCandles: ByteArray,
    val savedAtMillis: Long
)

@Dao
interface RangeTickSliceDao {
    @Query("""SELECT fromMillis, toMillis FROM verified_ctrader_bid_slices
        WHERE source = :source AND symbol = :symbol
        AND toMillis >= :from AND fromMillis <= :to
        ORDER BY fromMillis ASC, toMillis DESC""")
    suspend fun covered(source: String, symbol: String, from: Long, to: Long): List<RangeTickDiskSpan>

    @Query("""SELECT * FROM verified_ctrader_bid_slices
        WHERE source = :source AND symbol = :symbol
        AND fromMillis = :from AND toMillis = :to LIMIT 1""")
    suspend fun find(source: String, symbol: String, from: Long, to: Long): RangeTickSliceEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun save(slice: RangeTickSliceEntity)

    @Query("""DELETE FROM verified_ctrader_bid_slices
        WHERE source = :source AND symbol = :symbol
        AND fromMillis = :from AND toMillis = :to""")
    suspend fun discard(source: String, symbol: String, from: Long, to: Long)
}

@Dao
interface RangeBarSnapshotDao {
    @Query("""SELECT * FROM verified_ctrader_range_snapshots
        WHERE source = :source AND symbol = :symbol AND fromMillis = :from AND toMillis = :to
        AND rangeTicks = :size AND tickSizeBits = :tickSizeBits AND includeIncomplete = :includeIncomplete
        LIMIT 1""")
    suspend fun exact(source: String, symbol: String, from: Long, to: Long, size: Int,
                      tickSizeBits: Long, includeIncomplete: Boolean): RangeBarSnapshotEntity?

    @Query("""SELECT * FROM verified_ctrader_range_snapshots
        WHERE source = :source AND symbol = :symbol AND rangeTicks = :size
        AND tickSizeBits = :tickSizeBits AND includeIncomplete = :includeIncomplete
        AND toMillis BETWEEN :minimumTo AND :requestedTo
        ORDER BY toMillis DESC LIMIT 4""")
    suspend fun latest(source: String, symbol: String, size: Int, tickSizeBits: Long,
                       includeIncomplete: Boolean, minimumTo: Long,
                       requestedTo: Long): List<RangeBarSnapshotEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun save(snapshot: RangeBarSnapshotEntity)

    @Query("""DELETE FROM verified_ctrader_range_snapshots WHERE source = :source
        AND symbol = :symbol AND fromMillis = :from AND toMillis = :to
        AND rangeTicks = :size AND tickSizeBits = :tickSizeBits AND includeIncomplete = :includeIncomplete""")
    suspend fun discard(source: String, symbol: String, from: Long, to: Long, size: Int,
                        tickSizeBits: Long, includeIncomplete: Boolean)
}

@Database(entities = [RangeTickSliceEntity::class, RangeBarSnapshotEntity::class],
    version = 2, exportSchema = true)
abstract class RangeTickCacheDatabase : RoomDatabase() {
    abstract fun slices(): RangeTickSliceDao
    abstract fun bars(): RangeBarSnapshotDao

    companion object {
        @Volatile private var instance: RangeTickCacheDatabase? = null

        /** Non-destructive upgrade: keeps every verified BID tick slice from v1. */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("""CREATE TABLE IF NOT EXISTS verified_ctrader_range_snapshots
                    (source TEXT NOT NULL, symbol TEXT NOT NULL, fromMillis INTEGER NOT NULL,
                     toMillis INTEGER NOT NULL, rangeTicks INTEGER NOT NULL,
                     tickSizeBits INTEGER NOT NULL, includeIncomplete INTEGER NOT NULL,
                     compressedCandles BLOB NOT NULL, savedAtMillis INTEGER NOT NULL,
                     PRIMARY KEY(source, symbol, fromMillis, toMillis, rangeTicks, tickSizeBits, includeIncomplete))""")
                db.execSQL("""CREATE INDEX IF NOT EXISTS
                    index_verified_ctrader_range_snapshots_source_symbol_rangeTicks_toMillis
                    ON verified_ctrader_range_snapshots(source, symbol, rangeTicks, toMillis)""")
            }
        }

        fun getInstance(context: Context): RangeTickCacheDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(context.applicationContext,
                    RangeTickCacheDatabase::class.java, "tradelab_verified_bid_cache.db")
                    .addMigrations(MIGRATION_1_2)
                    .build().also { instance = it }
            }
    }
}
