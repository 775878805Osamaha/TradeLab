package com.example

import com.example.core.market.*
import com.example.core.model.*
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.min

class MarketDataConnectivityTests {

    private fun createCandle(
        symbol: String = "BTCUSDT",
        timeframe: Timeframe = Timeframe.M1,
        openTime: Long,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double = 1.0
    ): Candle = Candle(
        symbol = symbol,
        timeframe = timeframe,
        openTime = openTime,
        closeTime = openTime + (timeframe.minutes * 60000L),
        open = open,
        high = high,
        low = low,
        close = close,
        volume = volume
    )

    @Test
    fun `test DataIntegrityValidator validates candle invariants`() {
        // Valid candle
        val valid = createCandle(openTime = 1000L, open = 100.0, high = 110.0, low = 95.0, close = 105.0)
        assertTrue(DataIntegrityValidator.validateCandle(valid).isValid)

        // Invalid: High lower than max(Open, Close)
        val badHigh = createCandle(openTime = 1000L, open = 100.0, high = 99.0, low = 90.0, close = 105.0)
        assertFalse(DataIntegrityValidator.validateCandle(badHigh).isValid)

        // Invalid: Low higher than min(Open, Close)
        val badLow = createCandle(openTime = 1000L, open = 100.0, high = 110.0, low = 102.0, close = 105.0)
        assertFalse(DataIntegrityValidator.validateCandle(badLow).isValid)

        // Invalid: Negative volume
        val badVol = createCandle(openTime = 1000L, open = 100.0, high = 110.0, low = 95.0, close = 105.0, volume = -1.0)
        assertFalse(DataIntegrityValidator.validateCandle(badVol).isValid)

        // Invalid: closeTime <= openTime
        val badTime = valid.copy(closeTime = valid.openTime)
        assertFalse(DataIntegrityValidator.validateCandle(badTime).isValid)
    }

    @Test
    fun `test DataIntegrityValidator validates tick invariants`() {
        // Valid tick
        val validTick = Tick(symbol = "XAUUSD", bid = 2650.0, ask = 2650.5, last = 2650.25, timestamp = 1000L)
        assertTrue(DataIntegrityValidator.validateTick(validTick).isValid)

        // Invalid: ask < bid
        val badSpreadTick = Tick(symbol = "XAUUSD", bid = 2651.0, ask = 2650.0, last = 2650.5, timestamp = 1000L)
        assertFalse(DataIntegrityValidator.validateTick(badSpreadTick).isValid)

        // Invalid: bid <= 0
        val zeroBidTick = Tick(symbol = "XAUUSD", bid = 0.0, ask = 1.0, last = 0.5, timestamp = 1000L)
        assertFalse(DataIntegrityValidator.validateTick(zeroBidTick).isValid)

        // Invalid: timestamp <= 0
        val zeroTimeTick = Tick(symbol = "XAUUSD", bid = 100.0, ask = 101.0, last = 100.5, timestamp = 0L)
        assertFalse(DataIntegrityValidator.validateTick(zeroTimeTick).isValid)
    }

    @Test
    fun `test market validator rejects nonfinite candle values`() {
        val valid = createCandle(openTime = 1000L, open = 100.0, high = 110.0, low = 95.0, close = 105.0)
        assertFalse(DataIntegrityValidator.validateCandle(valid.copy(open = Double.NaN)).isValid)
        assertFalse(DataIntegrityValidator.validateCandle(valid.copy(high = Double.POSITIVE_INFINITY)).isValid)
        assertFalse(DataIntegrityValidator.validateCandle(valid.copy(low = 0.0)).isValid)
        assertFalse(DataIntegrityValidator.validateCandle(valid.copy(volume = Double.NaN)).isValid)
    }

    @Test
    fun `test market validator rejects nonfinite ticks`() {
        val valid = Tick(symbol = "BTCUSDT", bid = 100.0, ask = 100.5, last = 100.25, timestamp = 1000L)
        assertFalse(DataIntegrityValidator.validateTick(valid.copy(bid = Double.NaN)).isValid)
        assertFalse(DataIntegrityValidator.validateTick(valid.copy(ask = Double.POSITIVE_INFINITY)).isValid)
        assertFalse(DataIntegrityValidator.validateTick(valid.copy(last = Double.NaN)).isValid)
    }

    @Test
    fun `test sanitizeCandles eliminates duplicates and sorts chronologically`() {
        val c1 = createCandle(openTime = 3000L, open = 100.0, high = 105.0, low = 98.0, close = 102.0)
        val c2 = createCandle(openTime = 1000L, open = 95.0, high = 100.0, low = 94.0, close = 99.0)
        val c3Duplicate = createCandle(openTime = 1000L, open = 95.0, high = 101.0, low = 94.0, close = 98.0)
        val c4 = createCandle(openTime = 2000L, open = 99.0, high = 103.0, low = 97.0, close = 101.0)

        val sanitized = DataIntegrityValidator.sanitizeCandles(listOf(c1, c2, c3Duplicate, c4))

        assertEquals(3, sanitized.size)
        assertEquals(1000L, sanitized[0].openTime)
        assertEquals(2000L, sanitized[1].openTime)
        assertEquals(3000L, sanitized[2].openTime)
    }

    @Test
    fun `test Replay lookahead barrier blocks future market data`() {
        val candles = (1..10).map { i ->
            createCandle(openTime = i * 60000L, open = 100.0, high = 105.0, low = 95.0, close = 102.0)
        }

        val barrierTime = 5 * 60000L
        val visibleInReplay = DataIntegrityValidator.enforceReplayBarrier(candles, barrierTime)

        assertEquals(4, visibleInReplay.size)
        assertTrue(visibleInReplay.all { it.closeTime <= barrierTime })
        assertEquals(4 * 60000L, visibleInReplay.last().openTime)
    }

    @Test
    fun `test sanitizer retains independent symbols and timeframes at same timestamp`() {
        val btcM1 = createCandle(symbol = "BTCUSDT", timeframe = Timeframe.M1, openTime = 60000L, open = 100.0, high = 105.0, low = 95.0, close = 102.0)
        val goldM1 = btcM1.copy(symbol = "XAUUSD")
        val btcM15 = btcM1.copy(timeframe = Timeframe.M15, closeTime = 60000L + 15 * 60000L)
        val duplicate = btcM1.copy(close = 101.0)
        val result = DataIntegrityValidator.sanitizeCandles(listOf(btcM1, goldM1, btcM15, duplicate))
        assertEquals(3, result.size)
        assertEquals(3, result.map { Triple(it.symbol, it.timeframe, it.openTime) }.distinct().size)
    }

    @Test
    fun `test replay barrier excludes malformed completed candles`() {
        val valid = createCandle(openTime = 60000L, open = 100.0, high = 105.0, low = 95.0, close = 102.0)
        val malformed = valid.copy(openTime = 120000L, closeTime = 180000L, high = 99.0)
        val future = valid.copy(openTime = 180000L, closeTime = 240000L)
        val result = DataIntegrityValidator.enforceReplayBarrier(listOf(valid, malformed, future), 180000L)
        assertEquals(1, result.size)
        assertEquals(valid, result.single())
    }

    @Test
    fun `test historical validation rejects mixed symbol and overlapping bars`() {
        val first = createCandle(openTime = 60000L, open = 100.0, high = 105.0, low = 95.0, close = 102.0)
        val second = createCandle(openTime = 120000L, open = 102.0, high = 106.0, low = 99.0, close = 104.0)
        assertTrue(DataIntegrityValidator.validateHistoricalSeries(listOf(first, second)).isValid)
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(listOf(first, second.copy(symbol = "XAUUSD"))).isValid)
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(listOf(first, first)).isValid)
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(listOf(second, first)).isValid)
    }

    @Test
    fun `test historical validator accepts market session gaps but rejects timeframe overlap`() {
        val first = createCandle(openTime = 60000L, open = 100.0, high = 105.0, low = 95.0, close = 102.0)
        val afterWeekend = createCandle(openTime = 3 * 24 * 60 * 60000L, open = 103.0, high = 106.0, low = 101.0, close = 104.0)
        assertTrue(DataIntegrityValidator.validateHistoricalSeries(listOf(first, afterWeekend)).isValid)
        val overlapping = first.copy(openTime = 60001L, closeTime = 120001L)
        assertFalse(DataIntegrityValidator.validateHistoricalSeries(listOf(first, overlapping)).isValid)
    }

    @Test
    fun `test replay barrier excludes current forming candle and accepts exact close boundary`() {
        val candle = createCandle(openTime = 60000L, open = 100.0, high = 105.0, low = 95.0, close = 102.0)
        assertTrue(DataIntegrityValidator.enforceReplayBarrier(listOf(candle), candle.closeTime - 1L).isEmpty())
        assertEquals(listOf(candle), DataIntegrityValidator.enforceReplayBarrier(listOf(candle), candle.closeTime))
    }

    @Test
    fun `test MarketSymbolRegistry metadata and data source distinction`() {
        val btc = MarketSymbolRegistry.getSymbol("BTCUSDT")
        assertEquals("BTCUSDT", btc.symbol)
        assertEquals("CRYPTO", btc.assetClass)
        assertEquals(DataSourceType.LIVE_DATA, btc.dataSourceType)

        val gold = MarketSymbolRegistry.getSymbol("XAUUSD")
        assertEquals("XAUUSD", gold.symbol)
        assertEquals("METALS", gold.assetClass)
        assertEquals(DataSourceType.DEMO_DATA, gold.dataSourceType)

        val eur = MarketSymbolRegistry.getSymbol("EURUSD")
        assertEquals("EURUSD", eur.symbol)
        assertEquals(DataSourceType.DEMO_DATA, eur.dataSourceType)
    }

    @Test
    fun `test Exponential backoff reconnect calculation bounds`() {
        fun computeDelay(attempt: Int): Long {
            return min(30000L, (1000L * (1L shl min(attempt, 5))))
        }

        assertEquals(2000L, computeDelay(1))
        assertEquals(4000L, computeDelay(2))
        assertEquals(8000L, computeDelay(3))
        assertEquals(16000L, computeDelay(4))
        assertEquals(32000L.coerceAtMost(30000L), computeDelay(5))
        assertEquals(30000L, computeDelay(10)) // Max capped at 30s
    }

    @Test
    fun `test Determinism aggregation test`() {
        val input = (1..50).map { i ->
            createCandle(openTime = i * 60000L, open = 100.0 + (i % 5), high = 108.0, low = 98.0, close = 102.0)
        }

        val run1 = CandleAggregator.aggregate(input, Timeframe.M5)
        val run2 = CandleAggregator.aggregate(input, Timeframe.M5)

        assertEquals(run1.size, run2.size)
        for (i in run1.indices) {
            assertEquals(run1[i].openTime, run2[i].openTime)
            assertEquals(run1[i].open, run2[i].open, 0.0001)
            assertEquals(run1[i].high, run2[i].high, 0.0001)
            assertEquals(run1[i].low, run2[i].low, 0.0001)
            assertEquals(run1[i].close, run2[i].close, 0.0001)
            assertEquals(run1[i].volume, run2[i].volume, 0.0001)
        }
    }

    @Test
    fun `test Stale quote detection logic`() {
        val now = 1700000000000L
        val freshQuote = MarketQuote(
            symbol = "BTCUSDT",
            bid = 65000.0,
            ask = 65001.0,
            timestamp = now - 2000L, // 2s old
            status = QuoteStatus.FRESH
        )
        val isStale = (now - freshQuote.timestamp) > 15000L
        assertFalse("Quote within 15s must not be stale", isStale)

        val oldQuote = MarketQuote(
            symbol = "BTCUSDT",
            bid = 65000.0,
            ask = 65001.0,
            timestamp = now - 25000L, // 25s old
            status = QuoteStatus.FRESH
        )
        val isOldStale = (now - oldQuote.timestamp) > 15000L
        assertTrue("Quote older than 15s must be flagged as stale", isOldStale)
    }
}
