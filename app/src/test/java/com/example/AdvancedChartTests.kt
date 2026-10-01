package com.example

import com.example.core.indicators.TechnicalIndicators
import com.example.core.market.CandleAggregator
import com.example.core.model.*
import com.example.feature.chart.model.*
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.abs

class AdvancedChartTests {

    private fun createCandle(
        symbol: String = "XAUUSD",
        timeframe: Timeframe = Timeframe.M1,
        openTime: Long,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double = 10.0
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
    fun `test CandleAggregator aggregates M1 candles into M5 without lookahead`() {
        // 5 M1 candles at 0m, 1m, 2m, 3m, 4m
        val c1 = createCandle(openTime = 0L, open = 100.0, high = 105.0, low = 99.0, close = 103.0, volume = 5.0)
        val c2 = createCandle(openTime = 60000L, open = 103.0, high = 107.0, low = 102.0, close = 106.0, volume = 10.0)
        val c3 = createCandle(openTime = 120000L, open = 106.0, high = 106.5, low = 101.0, close = 102.0, volume = 8.0)
        val c4 = createCandle(openTime = 180000L, open = 102.0, high = 104.0, low = 98.0, close = 99.0, volume = 12.0)
        val c5 = createCandle(openTime = 240000L, open = 99.0, high = 108.0, low = 98.5, close = 107.5, volume = 15.0)

        val aggregated = CandleAggregator.aggregate(listOf(c1, c2, c3, c4, c5), Timeframe.M5)

        assertEquals(1, aggregated.size)
        val m5 = aggregated.first()
        assertEquals(0L, m5.openTime)
        assertEquals(100.0, m5.open, 0.001) // open of c1
        assertEquals(108.0, m5.high, 0.001) // max high (c5)
        assertEquals(98.0, m5.low, 0.001)   // min low (c4)
        assertEquals(107.5, m5.close, 0.001) // close of c5
        assertEquals(50.0, m5.volume, 0.001) // sum of volumes
        assertTrue("Aggregated closeTime must not exceed 5 minutes", m5.closeTime <= 300000L)
    }

    @Test
    fun `test CandleAggregator incremental live tick update`() {
        val c1 = createCandle(openTime = 0L, open = 2000.0, high = 2005.0, low = 1995.0, close = 2002.0)
        val list = listOf(c1)

        // Incoming tick inside current candle interval (at 30 seconds)
        val tick1 = Tick(symbol = "XAUUSD", bid = 2009.0, ask = 2010.0, last = 2010.0, timestamp = 30000L, volume = 2.0)
        val updated = CandleAggregator.updateWithTick(list, tick1, Timeframe.M1)

        assertEquals(1, updated.size)
        assertEquals(2010.0, updated[0].high, 0.001) // new high
        assertEquals(2010.0, updated[0].close, 0.001) // new close
        assertEquals(1995.0, updated[0].low, 0.001) // low unchanged

        // Incoming tick in NEW candle interval (at 65 seconds)
        val tick2 = Tick(symbol = "XAUUSD", bid = 2012.0, ask = 2013.0, last = 2012.5, timestamp = 65000L, volume = 1.0)
        val withNewCandle = CandleAggregator.updateWithTick(updated, tick2, Timeframe.M1)

        assertEquals(2, withNewCandle.size)
        assertEquals(60000L, withNewCandle[1].openTime)
        assertEquals(2012.5, withNewCandle[1].open, 0.001)
        assertEquals(2012.5, withNewCandle[1].close, 0.001)
    }

    @Test
    fun `test Indicators strictly enforce no lookahead`() {
        val candles = (1..30).map { i ->
            createCandle(openTime = i * 60000L, open = 100.0 + i, high = 105.0 + i, low = 95.0 + i, close = 102.0 + i)
        }

        val smaFull = TechnicalIndicators.calculateSma(candles, 10)
        val emaFull = TechnicalIndicators.calculateEma(candles, 10)
        val rsiFull = TechnicalIndicators.calculateRsi(candles, 14)
        val vwapFull = TechnicalIndicators.calculateVwap(candles)

        // Calculate for prefix 0..15 (candle index 15)
        val candlesPrefix = candles.take(16)
        val smaPrefix = TechnicalIndicators.calculateSma(candlesPrefix, 10)
        val emaPrefix = TechnicalIndicators.calculateEma(candlesPrefix, 10)
        val rsiPrefix = TechnicalIndicators.calculateRsi(candlesPrefix, 14)
        val vwapPrefix = TechnicalIndicators.calculateVwap(candlesPrefix)

        // Value at index 15 in prefix must match exactly the value at index 15 in full list (0 lookahead!)
        assertEquals("SMA at index 15 must not depend on future candles", smaFull[15], smaPrefix[15])
        assertEquals("EMA at index 15 must not depend on future candles", emaFull[15], emaPrefix[15])
        assertEquals("RSI at index 15 must not depend on future candles", rsiFull[15], rsiPrefix[15])
        assertEquals("VWAP at index 15 must not depend on future candles", vwapFull[15], vwapPrefix[15], 0.001)
    }

    @Test
    fun `test Bollinger Bands calculation`() {
        val candles = (1..25).map { i ->
            createCandle(openTime = i * 60000L, open = 100.0, high = 105.0, low = 95.0, close = 100.0 + (i % 3))
        }

        val bb = TechnicalIndicators.calculateBollingerBands(candles, period = 20, stdDevMultiplier = 2.0)
        assertEquals(25, bb.size)
        assertNull("Index 0 must be null (insufficient period)", bb[0])
        assertNotNull("Index 19 must have valid bands", bb[19])
        val res = bb[19]!!
        assertTrue("Upper band must be >= middle band", res.upper >= res.middle)
        assertTrue("Middle band must be >= lower band", res.middle >= res.lower)
    }

    @Test
    fun `test MACD and ATR calculations`() {
        val candles = (1..40).map { i ->
            createCandle(openTime = i * 60000L, open = 100.0 + i, high = 105.0 + i, low = 95.0 + i, close = 101.0 + i)
        }

        val macd = TechnicalIndicators.calculateMacd(candles, fastPeriod = 12, slowPeriod = 26, signalPeriod = 9)
        assertEquals(40, macd.size)
        val validMacd = macd.last()
        assertNotNull("Last MACD item must not be null", validMacd)
        assertEquals(validMacd!!.macd - validMacd.signal, validMacd.histogram, 0.001)

        val atr = TechnicalIndicators.calculateAtr(candles, 14)
        assertEquals(40, atr.size)
        assertNotNull("ATR should be calculated", atr.last())
        assertTrue("ATR must be positive", atr.last()!! > 0.0)
    }

    @Test
    fun `test ChartTransform coordinate safety without NaN or Infinity`() {
        val candles = listOf(
            createCandle(openTime = 1000L, open = 100.0, high = 110.0, low = 90.0, close = 105.0)
        )

        // Normal transform
        val transform = ChartTransform(
            visibleCandles = candles,
            minPrice = 90.0,
            maxPrice = 110.0,
            chartWidth = 500f,
            chartHeight = 300f,
            candleWidthPx = 20f
        )

        val y1 = transform.priceToY(100.0)
        assertFalse(y1.isNaN())
        assertFalse(y1.isInfinite())
        assertTrue(y1 in 0f..300f)

        // Test with NaN and Infinity input
        val yNaN = transform.priceToY(Double.NaN)
        val yInf = transform.priceToY(Double.POSITIVE_INFINITY)
        assertFalse("yNaN must be finite", yNaN.isNaN() || yNaN.isInfinite())
        assertFalse("yInf must be finite", yInf.isNaN() || yInf.isInfinite())

        // Test with equal min and max price (zero span)
        val flatTransform = ChartTransform(
            visibleCandles = candles,
            minPrice = 100.0,
            maxPrice = 100.0,
            chartWidth = 500f,
            chartHeight = 300f,
            candleWidthPx = 20f
        )
        val yFlat = flatTransform.priceToY(100.0)
        assertFalse("Flat transform must produce finite coordinates", yFlat.isNaN() || yFlat.isInfinite())
    }

    @Test
    fun `test FibonacciCalculator standard levels`() {
        val levels = FibonacciCalculator.calculateLevels(startPrice = 100.0, endPrice = 200.0)
        assertEquals(7, levels.size)

        // Level 0.0 = 100.0
        assertEquals(100.0, levels[0].second, 0.001)
        // Level 0.5 = 150.0
        val l50 = levels.first { it.first == 0.5 }
        assertEquals(150.0, l50.second, 0.001)
        // Level 1.0 = 200.0
        val l100 = levels.first { it.first == 1.0 }
        assertEquals(200.0, l100.second, 0.001)
    }

    @Test
    fun `test MeasurementCalculator calculates delta price, percentage, and duration`() {
        val result = MeasurementCalculator.calculate(
            startPrice = 100.0,
            endPrice = 110.0,
            startTime = 0L,
            endTime = 3600000L // 1 hour
        )

        assertEquals(10.0, result.priceDiff, 0.001)
        assertEquals(10.0, result.percentDiff, 0.001)
        assertEquals(3600000L, result.durationMillis)
        assertTrue(result.durationFormatted.contains("1h") || result.durationFormatted.contains("60m"))
    }

    @Test
    fun `test ChartDrawing Room entity serialization and deserialization`() {
        val drawing = ChartDrawing(
            id = 42L,
            tool = DrawingTool.TRENDLINE,
            symbol = "XAUUSD",
            timeframe = "M15",
            startPrice = 2650.0,
            startTime = 1700000000L,
            endPrice = 2670.0,
            endTime = 1700050000L,
            strokeWidth = 2.5f
        )

        val entity = drawing.toEntity()
        assertEquals(42L, entity.id)
        assertEquals("XAUUSD", entity.symbol)
        assertEquals("M15", entity.timeframe)
        assertEquals("TRENDLINE", entity.type)

        val restored = ChartDrawing.fromEntity(entity)
        assertNotNull(restored)
        assertEquals(drawing.id, restored!!.id)
        assertEquals(drawing.tool, restored.tool)
        assertEquals(drawing.startPrice, restored.startPrice, 0.001)
        assertEquals(drawing.endPrice!!, restored.endPrice!!, 0.001)
        assertEquals(drawing.startTime, restored.startTime)
        assertEquals(drawing.endTime, restored.endTime)
    }
}
