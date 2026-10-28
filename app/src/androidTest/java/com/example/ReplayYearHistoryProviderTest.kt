package com.example

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.core.market.HistoricalDataAudit
import com.example.core.market.ReplayDateHistory
import com.example.core.market.ReplayDateWindow
import com.example.core.model.Timeframe
import com.example.core.replay.HistoricalReplayEngine
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real provider coverage at the date this feature promises, with no generated bars. */
@RunWith(AndroidJUnit4::class)
class ReplayYearHistoryProviderTest {
    @Test fun yearOldGoldAndCryptoLoadIntoReplayWithoutRevealingLaterBars() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<TradeLabApplication>()
        val now = System.currentTimeMillis()
        val target = ReplayDateWindow.oneYearBefore(now)
        for ((symbol, timeframe) in listOf("XAUUSD" to Timeframe.D1, "BTCUSDT" to Timeframe.M1)) {
            val interval = timeframe.minutes * 60_000L
            var requests = 0
            val loaded = ReplayDateHistory.load(
                ReplayDateWindow.windows(target, now, interval, 300), target
            ) { from, to ->
                requests++
                app.marketDataRepository.getCandles(symbol, timeframe, from, to)
            }
            assertNotNull("Actual year-old $symbol/${timeframe.code} OHLC must be available", loaded)
            val candles = loaded!!.candles
            assertTrue(HistoricalDataAudit.inspect(candles, now).safeForBacktest)
            assertTrue(candles.all { it.symbol == symbol && it.timeframe == timeframe &&
                it.source in setOf("BIQUOTE_HISTORICAL", "TWELVE_DATA_HISTORICAL", "BINANCE_HISTORICAL", "BINANCE_HISTORICAL_CACHED") })
            val index = candles.indexOfFirst { it.openTime >= target }
            assertTrue(index >= 0)
            assertTrue("Must stay near the requested year-old date", candles[index].openTime < target + 7L*86_400_000L)
            val replay = HistoricalReplayEngine()
            replay.initialize(candles, index)
            assertEquals(candles[index], replay.currentCandle.value)
            assertEquals(candles.take(index + 1), replay.visibleCandles.value)
            assertTrue(replay.visibleCandles.value.all { it.openTime <= candles[index].openTime })
            android.util.Log.i("TradeLabYearHistory", "symbol=$symbol timeframe=${timeframe.code} target=$target first=${candles.first().openTime} last=${candles.last().openTime} count=${candles.size} requests=$requests")
        }
    }
}
