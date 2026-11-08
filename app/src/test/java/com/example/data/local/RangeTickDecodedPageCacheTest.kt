package com.example.data.local

import com.example.core.market.RangePriceTick
import org.junit.Assert.*
import org.junit.Test

class RangeTickDecodedPageCacheTest {
    private fun key(account: String, from: Long, to: Long) =
        RangeTickDecodedPageCache.Key("ctrader:demo:$account:12", "XAUUSD", from, to)

    @Test fun overlappingPanReusesIdenticalVerifiedQuoteObjectsWithoutDecompressingAgain() {
        val cache = RangeTickDecodedPageCache(maxQuotes = 3)
        val page = listOf(RangePriceTick(10L, 4071.0), RangePriceTick(11L, 4072.0))
        val range = key("7", 1L, 30L)
        cache.put(range, page)
        assertSame(page, cache.get(range))
        assertSame(page.first(), cache.get(range)!!.first())
        assertNull(cache.get(key("9", 1L, 30L)))
        assertEquals(1 to 2, cache.statistics())
    }

    @Test fun oldestPagesAreEvictedByQuoteBudgetAndRecentUsePreventsEviction() {
        val cache = RangeTickDecodedPageCache(maxQuotes = 3)
        val a = key("7", 1L, 30L)
        val b = key("7", 31L, 60L)
        val c = key("7", 61L, 90L)
        cache.put(a, listOf(RangePriceTick(10L, 4071.0)))
        cache.put(b, listOf(RangePriceTick(40L, 4072.0)))
        assertNotNull(cache.get(a)) // recent; B must leave first
        cache.put(c, listOf(RangePriceTick(80L, 4073.0), RangePriceTick(81L, 4074.0)))
        assertNotNull(cache.get(a))
        assertNull(cache.get(b))
        assertNotNull(cache.get(c))
        assertEquals(2 to 3, cache.statistics())
    }

    @Test fun hugeAndEmptyPagesNeverConsumeRetainedQuoteBudget() {
        val cache = RangeTickDecodedPageCache(maxQuotes = 1)
        cache.put(key("7", 1L, 30L), emptyList())
        cache.put(key("7", 31L, 60L), listOf(RangePriceTick(40L, 4072.0),
            RangePriceTick(41L, 4072.1)))
        assertEquals(0 to 0, cache.statistics())
        val one = key("7", 61L, 90L)
        cache.put(one, listOf(RangePriceTick(80L, 4073.0)))
        cache.remove(one)
        assertNull(cache.get(one))
        assertEquals(0 to 0, cache.statistics())
    }
}
