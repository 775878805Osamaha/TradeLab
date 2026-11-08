package com.example.core.market

import org.junit.Assert.*
import org.junit.Test

class RangeTickWindowReuseTest {
    private val quotes = listOf(
        RangePriceTick(100L, 4050.00),
        RangePriceTick(200L, 4050.01),
        RangePriceTick(200L, 4050.02),
        RangePriceTick(200L, 4050.03),
        RangePriceTick(300L, 4050.04),
        RangePriceTick(400L, 4050.05))

    @Test fun includesEverySameMillisecondPriceWithoutRetainingFutureQuotes() {
        val exact = RangeTickWindowReuse.between(quotes, 200L, 200L)
        assertEquals(quotes.subList(1, 4), exact)
        assertEquals(listOf(4050.01, 4050.02, 4050.03), exact.map { it.price })
        assertTrue(exact.none { it.timestamp > 200L })
    }

    @Test fun fullWindowReusesSourceListIdentityAndSlicedWindowDoesNot() {
        assertSame(quotes, RangeTickWindowReuse.between(quotes, 1L, 1_000L))
        assertNotSame(quotes, RangeTickWindowReuse.between(quotes, 200L, 300L))
        assertEquals(quotes.subList(1, 5), RangeTickWindowReuse.between(quotes, 200L, 300L))
    }

    @Test fun emptyAndOutOfRangeHistoryNeverProduceFabricatedQuotes() {
        assertTrue(RangeTickWindowReuse.between(emptyList(), 1L, 1_000L).isEmpty())
        assertTrue(RangeTickWindowReuse.between(quotes, 500L, 700L).isEmpty())
        assertTrue(RangeTickWindowReuse.between(quotes, 1L, 99L).isEmpty())
    }

    @Test fun everyRandomInclusiveWindowMatchesLiteralBrokerFilter() {
        // Deterministic regression over overlapping and single-ms windows.
        for (from in 1L..450L step 7L) {
            for (width in listOf(0L, 1L, 10L, 100L, 500L)) {
                val to = from + width
                assertEquals(quotes.filter { it.timestamp in from..to },
                    RangeTickWindowReuse.between(quotes, from, to))
            }
        }
    }
}
