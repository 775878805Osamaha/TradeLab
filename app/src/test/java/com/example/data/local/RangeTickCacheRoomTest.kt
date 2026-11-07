package com.example.data.local

import androidx.room.Room
import com.example.core.market.RangePriceTick
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
        try {
            Room.databaseBuilder(context, RangeTickCacheDatabase::class.java, dbName)
                .build().use { first ->
                    val saved = RangeTickDiskStore(first.slices()).getOrDownload(
                        "ctrader:demo:7:12", "XAUUSD", 1L, 300L) { _, _ -> expected }
                    assertEquals(expected, saved)
                }
            // A second database object emulates an Android process restart.
            Room.databaseBuilder(context, RangeTickCacheDatabase::class.java, dbName)
                .build().use { second ->
                    val restored = RangeTickDiskStore(second.slices()).getOrDownload(
                        "ctrader:demo:7:12", "XAUUSD", 50L, 300L) { _, _ ->
                            error("Reopening the chart must reuse the verified saved ticks")
                        }
                    assertEquals(expected, restored)
                }
        } finally {
            context.deleteDatabase(dbName)
        }
    }
}
