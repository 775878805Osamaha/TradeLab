package com.example.core.market

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CancellationException
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class RangeTickBatchLoaderTest {
    @Test fun measuredDensityStartsDeepPanWithOneLargerRequest() = runBlocking {
        val calls = mutableListOf<Pair<Long, Long>>()
        val from = 1L
        val to = 6L * 3_600_000L
        RangeTickBatchLoader.load(from, to, initialSliceMillis = 6L * 3_600_000L) { start, end ->
            calls.add(start to end)
            listOf(RangePriceTick(start, 4050.0), RangePriceTick(end, 4050.01))
        }
        assertEquals(listOf(from to to), calls)
    }

    @Test fun sparseSixHourHistoryUsesPreviewThenOneBulkRequest() = runBlocking {
        val from = 1L
        val to = from + 6L * 3_600_000L
        val calls = mutableListOf<Pair<Long, Long>>()
        RangeTickBatchLoader.load(from, to) { start, end ->
            calls.add(start to end)
            listOf(RangePriceTick(start, 4000.0), RangePriceTick(end, 4000.1))
        }
        assertEquals(2, calls.size)
        assertEquals(to - 3_600_000L + 1L to to, calls[0])
        assertEquals(from to (to - 3_600_000L), calls[1])
    }

    @Test fun transientGatewayFailuresRetryOnlyCurrentReadOnlyTickPage() = runBlocking {
        var attempts = 0
        val loaded = RangeTickBatchLoader.load(1L, 10L) { start, end ->
            attempts++
            if (attempts < 3) throw CTraderGatewayException(503, "ctrader_broker_unavailable")
            listOf(RangePriceTick(start, 4000.0), RangePriceTick(end, 4001.0))
        }
        assertEquals(3, attempts)
        assertEquals(listOf(1L, 10L), loaded.map { it.timestamp })
    }

    @Test fun permissionFailuresAreNeverRetransmittedAsTickRetries() = runBlocking {
        var attempts = 0
        try {
            RangeTickBatchLoader.load(1L, 10L) { _, _ ->
                attempts++
                throw CTraderGatewayException(403, "account_not_authorized")
            }
            fail("Permission failure must stop")
        } catch (expected: CTraderGatewayException) {
            assertEquals(403, expected.statusCode)
            assertEquals(1, attempts)
        }
    }

    @Test fun exactOneHourNeverTriggersSingleMillisecondExtraNetworkRequest() = runBlocking {
        val from = 1_000L
        val to = from + 3_600_000L
        val requests = mutableListOf<Pair<Long, Long>>()
        RangeTickBatchLoader.load(from, to) { start, end ->
            requests.add(start to end)
            listOf(RangePriceTick(start, 4000.0), RangePriceTick(end, 4000.1))
        }
        assertEquals(listOf(from to to), requests)
    }

    @Test fun highDensityRequestPlanUsesRealSubhourDurationInsteadOfRepeatedHourlySplits() {
        val hour = 3_600_000L
        assertEquals(6L * hour, RangeTickBatchLoader.nextSliceMillis(0, hour))
        assertEquals(9_000_000L, RangeTickBatchLoader.nextSliceMillis(20_000, hour))
        assertEquals(2_250_000L, RangeTickBatchLoader.nextSliceMillis(80_000, hour))
        assertEquals(60_000L, RangeTickBatchLoader.nextSliceMillis(4_000_000, hour))
    }

    @Test fun nextDenseBrokerWindowAdaptsToMeasuredQuotesWithoutGaps() = runBlocking {
        val hour = 3_600_000L
        val from = 1L
        val to = 2L * hour
        val requests = mutableListOf<Pair<Long, Long>>()
        val quotes = RangeTickBatchLoader.load(from, to) { start, end ->
            requests.add(start to end)
            if (requests.size == 1) List(80_000) { RangePriceTick(end, 4050.0) }
            else emptyList()
        }
        assertEquals(80_000, quotes.size)
        assertEquals(3, requests.size)
        assertEquals(2_250_000L, requests[1].second - requests[1].first + 1L)
        assertTrue(requests.zipWithNext().all { (newer, older) ->
            older.second + 1L == newer.first
        })
        assertEquals(from, requests.last().first)
    }

    @Test fun mostRecentBrokerSlicePaintsFirstButResultRemainsChronological() = runBlocking {
        val hour = 3_600_000L
        val from = 1L
        val to = 3L * hour
        val requests = mutableListOf<Pair<Long, Long>>()
        val previews = mutableListOf<List<RangePriceTick>>()
        val data = listOf(from, hour, hour + 1L, 2L * hour, to).mapIndexed { i, timestamp ->
            RangePriceTick(timestamp, 4000.0 + i)
        }
        val result = RangeTickBatchLoader.load(from, to,
            onNewestSlice = { previews.add(it) }) { start, end ->
            requests.add(start to end)
            data.filter { it.timestamp in start..end }
        }
        assertEquals(data, result)
        assertEquals(2L * hour + 1L to to, requests.first())
        assertEquals(1, previews.size)
        assertEquals(listOf(data.last()), previews.single())
        assertTrue(requests.zipWithNext().all { (newer, older) ->
            older.second + 1L == newer.first
        })
    }

    @Test fun growingPreviewsAlwaysContainVerifiedChronologicalSuffixAndNoFutureReplayQuote() = runBlocking {
        val hour = 3_600_000L
        val cutoff = 3L * hour
        val realQuotes = listOf(1L, hour, hour + 1L, 2L * hour, cutoff)
            .mapIndexed { index, time -> RangePriceTick(time, 4050.0 + index) }
        val initial = mutableListOf<List<RangePriceTick>>()
        val growing = mutableListOf<List<RangePriceTick>>()
        val finished = RangeTickBatchLoader.load(1L, cutoff,
            onNewestSlice = { initial += it.toList() },
            onGrowingHistory = { growing += it.toList() }) { start, end ->
            realQuotes.filter { it.timestamp in start..end }
        }
        assertEquals(realQuotes, finished)
        assertEquals(listOf(realQuotes.last()), initial.single())
        assertTrue("The chart must repaint before the final history batch", growing.isNotEmpty())
        assertEquals(realQuotes, growing.last())
        assertTrue(growing.all { suffix ->
            suffix.all { it.timestamp <= cutoff } &&
                suffix.zipWithNext().all { (left, right) -> left.timestamp <= right.timestamp } &&
                finished.takeLast(suffix.size) == suffix
        })
    }

    @Test fun denseSplitGrowingPreviewHasBoundedRebuildsAndNeverLosesRepeatedMillisecondQuotes() = runBlocking {
        val source = listOf(900L, 1_000L, 1_000L, 1_001L,
            1_500L, 1_500L, 1_800L, 2_000L)
            .mapIndexed { i, time -> RangePriceTick(time, 4050.0 + i * 0.01) }
        val previews = mutableListOf<List<RangePriceTick>>()
        val all = RangeTickBatchLoader.load(900L, 2_000L,
            onGrowingHistory = { previews += it.toList() }) { start, end ->
            if (end - start > 200L) throw RangeTickHistoryTooDenseException("hasMore")
            source.filter { it.timestamp in start..end }
        }
        assertEquals(source, all)
        assertTrue(previews.isNotEmpty())
        assertTrue("Growing previews must be logarithmically bounded", previews.size <= 4)
        assertTrue(previews.zipWithNext().all { (a, b) -> b.size >= a.size * 2 })
        assertTrue(previews.all { subset ->
            all.takeLast(subset.size) == subset &&
                subset.count { it.timestamp == 1_500L } <= 2
        })
        assertEquals(2, all.count { it.timestamp == 1_500L })
    }

    @Test fun exactSliceCountersNeverImplyUnfetchedTicksAreAlreadyAvailable() = runBlocking {
        val progress = mutableListOf<Pair<Int, Int>>()
        val bars = RangeTickBatchLoader.load(1L, 3_600_002L,
            onSliceComplete = { quotes, slices -> progress.add(quotes to slices) }) { start, end ->
            listOf(RangePriceTick(start, 4050.0), RangePriceTick(end, 4051.0))
        }
        assertEquals(listOf(2 to 1, 4 to 2), progress)
        assertEquals(4, bars.size)
        assertEquals(bars.size, progress.last().first)
    }

    @Test fun denseBrokerRequestsAreSplitIntoContiguousRealTickSlices() = runBlocking {
        val minute = 60_000L
        val from = 1L
        val to = from + 6L * 60L * minute
        val realTicks = (0..12).map { i ->
            RangePriceTick(from + i * 30L * minute, 2000.0 + i)
        }
        val requests = mutableListOf<Pair<Long, Long>>()
        val loaded = RangeTickBatchLoader.load(from, to) { start, end ->
            requests.add(start to end)
            if (end - start > 30L * minute)
                throw RangeTickHistoryTooDenseException("dense cTrader tick history")
            realTicks.filter { it.timestamp in start..end }
        }
        assertEquals(realTicks, loaded)
        assertTrue(requests.size > 2)
        assertTrue(requests.any { it.second - it.first <= 30L * minute })
        // If cTrader rejects a dense page, the newest half must be queried
        // first so the chart can show the most recent real quote promptly.
        val first = requests.first()
        val midpoint = first.first + (first.second - first.first) / 2L
        assertEquals(midpoint + 1L to first.second, requests[1])
    }

    @Test fun overloadedBrokerCannotLoseSameMillisecondQuotesAtPageBoundary() = runBlocking {
        val sourceQuotes = listOf(
            RangePriceTick(1_000L, 4050.00),
            RangePriceTick(1_000L, 4050.01),
            RangePriceTick(1_000L, 4050.02),
            RangePriceTick(1_001L, 4050.03),
            RangePriceTick(1_500L, 4050.04),
            RangePriceTick(1_500L, 4050.05),
            RangePriceTick(2_000L, 4050.06))
        val periods = mutableListOf<Pair<Long, Long>>()
        val progress = mutableListOf<Pair<Int, Int>>()
        val verifiedLeaves = mutableListOf<Pair<Long, Long>>()
        val recovered = RangeTickBatchLoader.load(900L, 2_000L,
            onSliceComplete = { quotes, slices -> progress.add(quotes to slices) },
            onVerifiedSlice = { start, end, _ -> verifiedLeaves.add(start to end) }) { start, end ->
            periods.add(start to end)
            // Emulate the server's hasMore marker: the truncated response is
            // not usable; force precise time bisection to fetch every quote.
            if (end - start > 200L)
                throw RangeTickHistoryTooDenseException("hasMore")
            sourceQuotes.filter { it.timestamp in start..end }
        }
        assertEquals(sourceQuotes, recovered)
        assertEquals(3, recovered.count { it.timestamp == 1_000L })
        assertEquals(2, recovered.count { it.timestamp == 1_500L })
        assertTrue(periods.any { it.second - it.first <= 200L })
        assertEquals(2_000L, verifiedLeaves.first().second)
        assertEquals(900L, verifiedLeaves.last().first)
        assertTrue(verifiedLeaves.zipWithNext().all { (newer, older) ->
            older.second + 1L == newer.first
        })
        // A dense hour exposes exact progress after every verified sub-page,
        // without waiting for all nested broker requests to finish.
        assertTrue(progress.size > 1)
        assertEquals(recovered.size, progress.last().first)
        assertEquals((1..progress.size).toList(), progress.map { it.second })
        assertTrue(progress.zipWithNext().all { (earlier, later) ->
            later.first >= earlier.first
        })
    }

    @Test fun cancelledNestedDenseSplitResumesFromExactVerifiedLeafBoundary() = runBlocking {
        val account = "ctrader:demo:123:987"
        val cache = RangeTickSuffixCache()
        val all = listOf(
            RangePriceTick(900L, 4050.00),
            RangePriceTick(1_000L, 4050.01),
            RangePriceTick(1_000L, 4050.02),
            RangePriceTick(1_500L, 4050.03),
            RangePriceTick(1_800L, 4050.04),
            RangePriceTick(2_000L, 4050.05))
        var verifiedLeaves = 0
        try {
            RangeTickBatchLoader.load(900L, 2_000L,
                onVerifiedSlice = { start, end, quotes ->
                    cache.remember("XAUUSD", account, start, end, quotes)
                    verifiedLeaves++
                    if (verifiedLeaves == 2) throw CancellationException("view switched")
                }) { start, end ->
                if (end - start > 200L) throw RangeTickHistoryTooDenseException("hasMore")
                all.filter { it.timestamp in start..end }
            }
            fail("Expected the chart request to be cancelled")
        } catch (_: CancellationException) { }
        val suffix = cache.snapshot("XAUUSD", account, 900L, 2_000L)!!
        assertEquals(2, verifiedLeaves)
        assertTrue(suffix.from > 900L)
        assertEquals(2_000L, suffix.to)
        val resumedIntervals = mutableListOf<Pair<Long, Long>>()
        val older = RangeTickBatchLoader.load(900L, suffix.from - 1L) { start, end ->
            resumedIntervals.add(start to end)
            if (end - start > 200L) throw RangeTickHistoryTooDenseException("hasMore")
            all.filter { it.timestamp in start..end }
        }
        assertEquals(all, older + suffix.ticks)
        assertTrue(resumedIntervals.all { it.second < suffix.from })
    }

    @Test fun sameMillisecondBrokerOverflowFailsExplicitlyWithoutInventingQuotes() = runBlocking {
        try {
            RangeTickBatchLoader.load(1_000L, 1_000L) { _, _ ->
                throw RangeTickHistoryTooDenseException("hasMore")
            }
            fail("A single millisecond cannot be split further")
        } catch (expected: RangeTickHistoryTooDenseException) {
            assertEquals("hasMore", expected.message)
        }
    }

    @Test fun consecutiveBrokerSlicesDoNotRepeatBoundaryTicks() = runBlocking {
        val hour = 3_600_000L
        val from = 1L
        val to = 12L * hour
        val expected = listOf(from, 6L * hour, 6L * hour + 1L, to)
        val result = RangeTickBatchLoader.load(from, to) { start, end ->
            expected.filter { it in start..end }.map { RangePriceTick(it, 2070.0) }
        }
        assertEquals(expected, result.map { it.timestamp })
    }

    @Test fun unavailableBrokerDataIsNotSwallowedOrFabricated() = runBlocking {
        try {
            RangeTickBatchLoader.load(1L, 7L) { _, _ ->
                throw IOException("broker unavailable")
            }
            fail("Unavailable broker quotes must fail")
        } catch (expected: IOException) {
            assertEquals("broker unavailable", expected.message)
        }
    }

    @Test fun rejectsInvalidTickPageInsteadOfDisplayingMisorderedBars() = runBlocking {
        try {
            RangeTickBatchLoader.load(1L, 9L) { _, _ ->
                listOf(RangePriceTick(8L, 2000.0), RangePriceTick(7L, 2000.1))
            }
            fail("Unordered quotes must fail")
        } catch (expected: IllegalArgumentException) {
            assertTrue(expected.message.orEmpty().contains("Invalid ordered"))
        }
    }

    @Test fun rejectedSliceCannotBeSavedAsVerifiedProgress() = runBlocking {
        var accepted = 0
        try {
            RangeTickBatchLoader.load(1L, 100L,
                onVerifiedSlice = { _, _, _ -> accepted++ }) { _, _ ->
                listOf(RangePriceTick(100L, 4050.0), RangePriceTick(99L, 4051.0))
            }
            fail("Unordered prices must not be persisted")
        } catch (_: IllegalArgumentException) { }
        assertEquals(0, accepted)
    }

    @Test fun mergedWindowBudgetIsCheckedBeforePersistingAnOversizedBrokerLeaf() = runBlocking {
        var verified = 0
        try {
            RangeTickBatchLoader.load(1L, 100L,
                maxAllowedTicks = 3,
                onVerifiedSlice = { _, _, _ -> verified++ }) { start, end ->
                listOf(1L, 2L, 3L, 4L).map { t ->
                    RangePriceTick(t.coerceIn(start, end), 4050.0)
                }
            }
            fail("The already-cached quotes reserve the rest of the tick budget")
        } catch (_: RangeTickHistoryTooDenseException) { }
        assertEquals(0, verified)
    }
}
