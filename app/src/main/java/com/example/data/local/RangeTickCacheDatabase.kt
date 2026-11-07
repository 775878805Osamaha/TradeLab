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

@Database(entities = [RangeTickSliceEntity::class], version = 1, exportSchema = true)
abstract class RangeTickCacheDatabase : RoomDatabase() {
    abstract fun slices(): RangeTickSliceDao

    companion object {
        @Volatile private var instance: RangeTickCacheDatabase? = null

        fun getInstance(context: Context): RangeTickCacheDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(context.applicationContext,
                    RangeTickCacheDatabase::class.java, "tradelab_verified_bid_cache.db")
                    .build().also { instance = it }
            }
    }
}
