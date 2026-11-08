package com.example.core.market

import kotlinx.coroutines.CancellationException
import org.junit.Assert.*
import org.junit.Test

class VerifiedRangeAccumulatorTest {
    private val source = "ctrader:demo:123:456"
    private fun quote(i: Int) = RangePriceTick(1_000L + i / 3,
        4050.0 + (i % 25) * 0.01)

    @Test fun splitAtEveryQuoteMatchesOnePassIncludingFormingBarAndDiagnostics() {
        val all = (0..200).map(::quote)
        for (split in all.indices) {
            val incremental = VerifiedRangeAccumulator("XAUUSD", 0.01, 10, source)
            incremental.append(all.subList(0, split))
            val halfway = incremental.snapshot(includeIncomplete = true)
            assertEquals(split, halfway.diagnostics.quoteCount)
            incremental.append(all.subList(split, all.size))
            val expected = RangeBarsEngine.buildVerified("XAUUSD", all, 0.01, 10,
                source, includeIncomplete = true)
            assertEquals("split=$split", expected, incremental.snapshot(true))
            assertEquals("split=$split", RangeBarsEngine.buildVerified(
                "XAUUSD", all, 0.01, 10, source), incremental.snapshot(false))
        }
    }

    @Test fun forkAndAppendDoNotMutateTheAlreadyPublishedReplaySnapshot() {
        val original = VerifiedRangeAccumulator("XAUUSD", 0.01, 100, source)
        original.append(listOf(RangePriceTick(100L, 4050.00), RangePriceTick(110L, 4050.40)))
        val published = original.snapshot(includeIncomplete = true)
        val continuation = original.fork()
        continuation.append(listOf(RangePriceTick(120L, 4051.00),
            RangePriceTick(130L, 4051.10)))
        assertEquals(2, original.snapshot(true).diagnostics.quoteCount)
        assertEquals(4, continuation.snapshot(true).diagnostics.quoteCount)
        assertEquals(4050.40, published.candles.last().close, 0.0)
        assertEquals(published, original.snapshot(true))
        assertEquals(RangeBarsEngine.buildVerified("XAUUSD", listOf(
            RangePriceTick(100L, 4050.00), RangePriceTick(110L, 4050.40),
            RangePriceTick(120L, 4051.00), RangePriceTick(130L, 4051.10)),
            0.01, 100, source, true), continuation.snapshot(true))
    }

    @Test fun canceledForkCannotCorruptPreviouslyCompletedRangeBars() {
        val accumulator = VerifiedRangeAccumulator("XAUUSD", 0.01, 100, source)
        val prefix = (0..100).map(::quote)
        accumulator.append(prefix)
        val before = accumulator.snapshot(true)
        val canceled = accumulator.fork()
        try {
            canceled.append((101..20_000).map(::quote)) {
                throw CancellationException("obsolete Replay cutoff")
            }
            fail("Canceled tick processing must stop")
        } catch (expected: CancellationException) {
            assertEquals("obsolete Replay cutoff", expected.message)
        }
        assertEquals(before, accumulator.snapshot(true))
    }

    @Test fun unchangedPrefixProvesIdentityNotJustEqualPricesOrTimestamps() {
        val original = (0..100).map(::quote)
        val appended = original + (101..120).map(::quote)
        assertEquals(original.size, RangeVerifiedPrefix.reusableQuoteCount(original, appended))
        assertEquals(0, RangeVerifiedPrefix.reusableQuoteCount(original,
            appended.toMutableList().apply { this[50] = quote(50) }))
        assertEquals(0, RangeVerifiedPrefix.reusableQuoteCount(original, appended.drop(1)))
        assertEquals(0, RangeVerifiedPrefix.reusableQuoteCount(original, original.dropLast(1)))
    }

    @Test fun incrementalPrefixScanChecksCancellationDuringLargeQuoteHistory() {
        val historical = (0..50_000).map(::quote)
        var checkpoints = 0
        try {
            RangeVerifiedPrefix.reusableQuoteCount(historical, historical) {
                if (++checkpoints == 2) throw CancellationException("stale request")
            }
            fail("Expected cancellation during a long verified-prefix scan")
        } catch (expected: CancellationException) {
            assertEquals(2, checkpoints)
        }
    }
}
