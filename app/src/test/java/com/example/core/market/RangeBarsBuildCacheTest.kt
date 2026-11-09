package com.example.core.market

import org.junit.Assert.*
import org.junit.Test

class RangeBarsBuildCacheTest {
    private val source = "ctrader:demo:123:456"
    private val prices = listOf(RangePriceTick(100L, 4000.0),
        RangePriceTick(101L, 4001.0), RangePriceTick(102L, 4002.0))

    @Test fun exactQuoteIdentityAndAllConstructionInputsAreRequired() {
        val cache = RangeBarsBuildCache()
        val result = RangeBarsEngine.buildVerified("XAUUSD", prices, 0.01, 100, source)
        cache.remember(prices, "XAUUSD", source, 0.01, 100, false, result)
        assertSame(result, cache.find(prices, "XAUUSD", source, 0.01, 100, false))
        assertNull(cache.find(prices.toList().toMutableList(), "XAUUSD", source, 0.01, 100, false))
        assertNull(cache.find(prices, "XAUUSD", source, 0.01, 100, true))
        assertNull(cache.find(prices, "XAUUSD", source, 0.01, 1000, false))
        assertNull(cache.find(prices, "XAUUSD", "ctrader:demo:other:456", 0.01, 100, false))
        assertNull(cache.find(prices, "EURUSD", source, 0.01, 100, false))
        assertNull(cache.find(prices, "XAUUSD", source, 0.001, 100, false))
    }

    @Test fun advancingOrBackfillingWindowDiscardsAllStaleBars() {
        val cache = RangeBarsBuildCache()
        val earlier = listOf(RangePriceTick(99L, 3999.0)) + prices
        val oldResult = RangeBarsEngine.buildVerified("XAUUSD", prices, 0.01, 100, source)
        val newResult = RangeBarsEngine.buildVerified("XAUUSD", earlier, 0.01, 100, source)
        cache.remember(prices, "XAUUSD", source, 0.01, 100, false, oldResult)
        cache.remember(earlier, "XAUUSD", source, 0.01, 100, false, newResult)
        assertNull(cache.find(prices, "XAUUSD", source, 0.01, 100, false))
        assertSame(newResult, cache.find(earlier, "XAUUSD", source, 0.01, 100, false))
        cache.clear()
        assertNull(cache.find(earlier, "XAUUSD", source, 0.01, 100, false))
    }

    @Test fun cacheKeepsOnlyTwoSizesForOneQuoteWindow() {
        val cache = RangeBarsBuildCache(2)
        listOf(50, 100, 1000).forEach { size ->
            cache.remember(prices, "XAUUSD", source, 0.01, size, false,
                RangeBarsEngine.buildVerified("XAUUSD", prices, 0.01, size, source))
        }
        assertNull(cache.find(prices, "XAUUSD", source, 0.01, 50, false))
        assertNotNull(cache.find(prices, "XAUUSD", source, 0.01, 100, false))
        assertNotNull(cache.find(prices, "XAUUSD", source, 0.01, 1000, false))
    }
}
