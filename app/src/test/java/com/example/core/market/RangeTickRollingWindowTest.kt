package com.example.core.market

import kotlinx.coroutines.CancellationException
import org.junit.Assert.*
import org.junit.Test

class RangeTickRollingWindowTest {
    private val source = "ctrader:demo:account1"
    private fun quote(time: Long, cents: Int = 0) =
        RangePriceTick(time, 4050.00 + cents * 0.01)
    private fun window(from: Long, to: Long, vararg quotes: RangePriceTick) =
        RangeTickRollingWindow.Window("XAUUSD", source, from, to, quotes.toList())

    @Test fun backwardThenForwardReusesVerifiedUnionWithoutDuplicatingOverlap() {
        val recent = window(201L, 500L, quote(201L), quote(300L), quote(500L))
        val older = window(101L, 400L, quote(101L), quote(201L), quote(300L))
        val combined = RangeTickRollingWindow.extend(recent, older)
        assertEquals(101L, combined.from)
        assertEquals(500L, combined.to)
        assertEquals(listOf(101L, 201L, 300L, 500L), combined.ticks.map { it.timestamp })

        // A normal pan forward is now covered by the same exact broker quotes.
        assertSame(combined, RangeTickRollingWindow.extend(combined, recent))
        assertEquals(recent.ticks, RangeTickWindowReuse.between(combined.ticks, 201L, 500L))
    }

    @Test fun keepsAllSameMillisecondBidChangesAtTheHistoricalBoundary() {
        val recent = window(200L, 400L,
            quote(200L, 1), quote(200L, 2), quote(400L, 3))
        val older = window(100L, 250L,
            quote(100L), quote(200L, 1), quote(200L, 2))
        val combined = RangeTickRollingWindow.extend(recent, older)
        assertEquals(listOf(100L, 200L, 200L, 400L), combined.ticks.map { it.timestamp })
        assertEquals(listOf(4050.01, 4050.02),
            RangeTickWindowReuse.between(combined.ticks, 200L, 200L).map { it.price })
    }

    @Test fun replayNeverReceivesFutureQuotesEvenWhenCacheRetainsThem() {
        val recent = window(200L, 500L,
            quote(200L, 0), quote(300L, 5), quote(400L, 10), quote(500L, 15))
        val replay = window(100L, 350L,
            quote(100L, 0), quote(200L, 0), quote(300L, 5))
        val retained = RangeTickRollingWindow.extend(recent, replay)
        assertEquals(500L, retained.to)
        val visibleOnly = RangeTickWindowReuse.between(retained.ticks, 100L, 350L)
        assertEquals(300L, visibleOnly.last().timestamp)
        val bars = RangeBarsEngine.buildVerified("XAUUSD", visibleOnly, 0.01, 5,
            source, includeIncomplete = true)
        assertTrue(bars.candles.all { it.openTime <= 350L && it.closeTime <= 351L })
        assertEquals(visibleOnly.size, bars.diagnostics.quoteCount)
    }

    @Test fun denseOrTooLongUnionFallsBackToCompleteVisibleWindow() {
        val earlier = window(100L, 300L, quote(100L), quote(200L), quote(300L))
        val recent = window(200L, 400L, quote(200L), quote(300L), quote(400L))
        assertSame(recent, RangeTickRollingWindow.extend(earlier, recent, maxTicks = 3))
        assertSame(recent, RangeTickRollingWindow.extend(earlier, recent, maxSpanMillis = 250L))
    }

    @Test fun differentBrokerAccountCannotContaminateAReplayWindow() {
        val old = window(100L, 200L, quote(100L), quote(200L))
        val differentAccount = old.copy(source = "ctrader:live:account2")
        assertSame(differentAccount, RangeTickRollingWindow.extend(old, differentAccount))
    }

    @Test fun measuredDensityChoosesSmallerFirstPageForDenseGold() {
        val dense = RangeTickRollingWindow.Window("XAUUSD", source,
            1L, 3_600_000L, List(80_000) { quote(3_600_000L) })
        assertEquals(2_250_000L, RangeTickRollingWindow.initialSliceMillis(dense))
        assertEquals(3_600_000L, RangeTickRollingWindow.initialSliceMillis(null))
    }

    @Test fun largeRangeRebuildHonorsCancellationBeforeProcessingEveryQuote() {
        val quotes = List(20_000) { i -> quote(i + 1L, i % 2) }
        var checks = 0
        try {
            RangeBarsEngine.buildVerified("XAUUSD", quotes, 0.01, 5, source,
                cancellationCheckpoint = {
                    if (++checks == 2) throw CancellationException("obsolete pan")
                })
            fail("Canceled deep history work must not rebuild all historical ticks")
        } catch (expected: CancellationException) {
            assertEquals("obsolete pan", expected.message)
            assertEquals(2, checks)
        }
    }
}
