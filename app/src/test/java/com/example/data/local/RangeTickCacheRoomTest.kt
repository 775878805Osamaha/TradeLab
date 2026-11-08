package com.example.data.local

import androidx.room.Room
import android.content.Context
import com.example.core.market.RangeTickCacheCodec
import com.example.core.market.RangeTickDiagnostics
import com.example.core.market.VerifiedRangeBars
import com.example.core.market.RangePriceTick
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Actual SQLite persistence across a fully closed/reopened Android Room DB. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class RangeTickCacheRoomTest {
    @Test fun savedCTraderQuotesSurviveDatabaseReopenAndReadWithoutBroker() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val dbName = "verified_bid_cache_reopen_test.db"
        context.deleteDatabase(dbName)
        val expected = listOf(RangePriceTick(100, 4071.37), RangePriceTick(100, 4071.38),
            RangePriceTick(250, 4078.9))
        val result = VerifiedRangeBars(listOf(Candle("XAUUSD", Timeframe.M1, 100L, 251L,
            4071.37, 4081.37, 4070.0, 4078.9, 0.0, "ctrader:demo:7:12")),
            RangeTickDiagnostics(3), true)
        try {
            val first = Room.databaseBuilder(context, RangeTickCacheDatabase::class.java, dbName)
                .build()
            try {
                val saved = RangeTickDiskStore(first.slices()).getOrDownload(
                    "ctrader:demo:7:12", "XAUUSD", 1L, 300L) { _, _ -> expected }
                assertEquals(expected, saved)
                RangeBarDiskStore(first.bars()).save("XAUUSD", "ctrader:demo:7:12",
                    1L, 300L, 1000, 0.01, true, result)
            } finally { first.close() }
            // A second database object emulates an Android process restart.
            val second = Room.databaseBuilder(context, RangeTickCacheDatabase::class.java, dbName)
                .build()
            try {
                val restored = RangeTickDiskStore(second.slices()).getOrDownload(
                    "ctrader:demo:7:12", "XAUUSD", 50L, 300L) { _, _ ->
                        error("Reopening the chart must reuse the verified saved ticks")
                    }
                assertEquals(expected, restored)
                assertEquals(result, RangeBarDiskStore(second.bars()).exact(
                    "XAUUSD", "ctrader:demo:7:12", 1L, 300L, 1000, 0.01, true))
            } finally { second.close() }
        } finally {
            context.deleteDatabase(dbName)
        }
    }

    @Test fun upgradingV1BidCacheToV2PreservesAlreadyDownloadedQuotes() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val dbName = "verified_bid_cache_v1_upgrade_test.db"
        context.deleteDatabase(dbName)
        val quotes = listOf(RangePriceTick(100L, 4071.37))
        try {
            // This is the original v1 schema, with actual cached quotes.
            val old = context.openOrCreateDatabase(dbName, Context.MODE_PRIVATE, null)
            try {
                old.execSQL("""CREATE TABLE verified_ctrader_bid_slices
                    (source TEXT NOT NULL, symbol TEXT NOT NULL, fromMillis INTEGER NOT NULL,
                     toMillis INTEGER NOT NULL, quoteCount INTEGER NOT NULL,
                     compressedBidQuotes BLOB NOT NULL, savedAtMillis INTEGER NOT NULL,
                     PRIMARY KEY(source, symbol, fromMillis, toMillis))""")
                old.execSQL("""CREATE INDEX index_verified_ctrader_bid_slices_source_symbol_toMillis
                    ON verified_ctrader_bid_slices(source, symbol, toMillis)""")
                old.execSQL("""INSERT INTO verified_ctrader_bid_slices
                    (source, symbol, fromMillis, toMillis, quoteCount, compressedBidQuotes, savedAtMillis)
                    VALUES (?, ?, ?, ?, ?, ?, ?)""", arrayOf("ctrader:demo:7:12", "XAUUSD",
                    1L, 300L, 1, RangeTickCacheCodec.encode(quotes, 1L, 300L), 100L))
                old.version = 1
            } finally { old.close() }
            val upgraded = Room.databaseBuilder(context, RangeTickCacheDatabase::class.java, dbName)
                .addMigrations(RangeTickCacheDatabase.MIGRATION_1_2).build()
            try {
                val reloaded = RangeTickDiskStore(upgraded.slices()).getOrDownload(
                    "ctrader:demo:7:12", "XAUUSD", 1L, 300L) { _, _ ->
                    error("A database upgrade must never redownload or erase valid BID quotes")
                }
                assertEquals(quotes, reloaded)
            } finally { upgraded.close() }
        } finally { context.deleteDatabase(dbName) }
    }

    @Test fun latestReplaySnapshotReopensExactlyAndKeepsAllOriginalBidQuotes() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val dbName = "verified_bid_cache_coalescing_reopen_test.db"
        context.deleteDatabase(dbName)
        val source = "ctrader:demo:7:12"
        val quotes = listOf(RangePriceTick(100L, 4071.37),
            RangePriceTick(101L, 4072.37))
        val oldBars = VerifiedRangeBars(listOf(Candle("XAUUSD", Timeframe.M1,
            100L, 102L, 4071.37, 4081.37, 4070.0, 4072.37, 0.0, source)),
            RangeTickDiagnostics(2), true)
        val newBars = VerifiedRangeBars(listOf(Candle("XAUUSD", Timeframe.M1,
            100L, 103L, 4071.37, 4081.37, 4070.0, 4072.37, 0.0, source)),
            RangeTickDiagnostics(2), true)
        try {
            val first = Room.databaseBuilder(context, RangeTickCacheDatabase::class.java, dbName)
                .build()
            try {
                RangeTickDiskStore(first.slices()).getOrDownload(source, "XAUUSD", 1L, 300L) {
                    _, _ -> quotes
                }
                val snapshots = RangeBarDiskStore(first.bars())
                snapshots.save("XAUUSD", source, 1L, 300L, 1000, 0.01, true, oldBars)
                snapshots.save("XAUUSD", source, 1L, 301L, 1000, 0.01, true, newBars)
            } finally { first.close() }
            val reopened = Room.databaseBuilder(context, RangeTickCacheDatabase::class.java, dbName)
                .build()
            try {
                val snapshots = RangeBarDiskStore(reopened.bars())
                assertEquals(newBars, snapshots.exact("XAUUSD", source, 1L, 301L,
                    1000, 0.01, true))
                assertEquals(null, snapshots.exact("XAUUSD", source, 1L, 300L,
                    1000, 0.01, true))
                assertEquals(quotes, RangeTickDiskStore(reopened.slices()).getOrDownload(
                    source, "XAUUSD", 1L, 300L) { _, _ ->
                    error("Snapshot coalescing must never delete the original BID history")
                })
            } finally { reopened.close() }
        } finally { context.deleteDatabase(dbName) }
    }
}
