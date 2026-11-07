package com.example.core.market

import org.junit.Assert.*
import org.junit.Test

class RangeBarsEngineTest {
    private val source = "ctrader:demo:123:456"

    @Test fun diagnosticCountsReflectExactRealQuotesWithoutReconstructingPrices() {
        val ticks = listOf(
            RangePriceTick(1_000L, 2000.0),
            RangePriceTick(1_000L, 2000.25),
            RangePriceTick(1_500L, 2020.0))
        val computed = RangeBarsEngine.buildVerified("XAUUSD", ticks, 0.01, 100, source)
        assertEquals(RangeBarsEngine.build("XAUUSD", ticks, 0.01, 100, source), computed.candles)
        assertEquals(3, computed.diagnostics.quoteCount)
        assertEquals(1, computed.diagnostics.sameMillisecondQuotes)
        assertEquals(1, computed.diagnostics.jumpsOverOneRange)
        assertEquals(1975L, computed.diagnostics.largestQuoteJumpTicks)
        assertEquals(500L, computed.diagnostics.longestQuotePauseMillis)
        assertEquals(1, computed.diagnostics.oversizedCandles)
        assertEquals(2020.0, computed.candles.single().close, 0.0)
    }

    @Test fun emptyBrokerQuotesHaveZeroMetricsAndNoInventedCandles() {
        val computed = RangeBarsEngine.buildVerified("XAUUSD", emptyList(), 0.01, 100, source)
        assertTrue(computed.candles.isEmpty())
        assertEquals(RangeTickDiagnostics(), computed.diagnostics)
    }

    @Test fun fixedThousandPriceTicksBuildActualGoldRanges() {
        val points = listOf(2000.0, 2004.0, 2010.0, 2010.5, 2008.0, 1999.5)
            .mapIndexed { i, price -> RangePriceTick(1_000L + i * 1000, price) }
        val bars = RangeBarsEngine.build("XAUUSD", points, 0.01, 1000, source)
        assertEquals(2, bars.size)
        assertEquals(2000.0, bars[0].open, 0.0)
        assertEquals(2010.0, bars[0].close, 0.0)
        assertEquals(2010.0, bars[1].open, 0.0)
        assertEquals(1999.5, bars[1].close, 0.0)
        assertTrue(bars.all { it.isValid() && it.volume == 0.0 && it.source == source })
    }

    @Test fun gapUsesTrueBrokerQuoteWithoutSyntheticIntermediateBars() {
        val bars = RangeBarsEngine.build("XAUUSD",
            listOf(RangePriceTick(1, 2000.0), RangePriceTick(2, 2040.0)),
            0.01, 1000, source)
        assertEquals(1, bars.size)
        assertEquals(2040.0, bars.single().high, 0.0)
    }

    @Test fun adjacentRangeBarsShareActualClosingQuoteAndHaveNoArtificialOpenGap() {
        val ticks = listOf(4000.0, 4000.5, 4001.0, 4001.5, 4002.0, 4001.0)
            .mapIndexed { i, price -> RangePriceTick(10_000L + i, price) }
        val bars = RangeBarsEngine.build("XAUUSD", ticks, 0.01, 100, source)
        assertEquals(3, bars.size)
        assertEquals(listOf(4000.0, 4001.0, 4002.0), bars.map { it.open })
        assertEquals(listOf(4001.0, 4002.0, 4001.0), bars.map { it.close })
        assertTrue(bars.zipWithNext().all { (a, b) -> a.close == b.open })
        assertTrue(bars.all { it.source == source && it.isValid() })
    }

    @Test fun largeUntradedJumpIsKeptRealAndNextRangeBeginsAtItsActualClose() {
        val ticks = listOf(RangePriceTick(10, 4050.0), RangePriceTick(11, 4065.0),
            RangePriceTick(12, 4064.0))
        val bars = RangeBarsEngine.build("XAUUSD", ticks, 0.01, 100, source)
        assertEquals(2, bars.size)
        assertEquals(15.0, bars.first().high - bars.first().low, 1e-8)
        assertEquals(4065.0, bars[1].open, 0.0)
        assertEquals(4064.0, bars[1].close, 0.0)
    }

    @Test fun visibleRangeChartNeverFabricatesIntermediatePricesWithinRealBar() {
        val ticks = listOf(RangePriceTick(10, 4050.0), RangePriceTick(11, 4065.0),
            RangePriceTick(12, 4064.0))
        val actual = RangeBarsEngine.build("XAUUSD", ticks, 0.01, 100, source)
        val displayed = RangePhantomBars.project(actual, 0.01, 100)
        assertEquals(2, actual.size)
        assertEquals(actual, displayed)
        assertTrue(displayed.zipWithNext().all { (left, right) ->
            kotlin.math.abs(left.close - right.open) < 1e-8
        })
        assertTrue(displayed.none(RangePhantomBars::isPhantom))
        assertEquals(4065.0, actual[0].close, 0.0)
        assertEquals(4064.0, actual[1].close, 0.0)
    }

    @Test fun unfinishedBarIsHiddenInReplayButVisibleInAnalysis() {
        val points = listOf(RangePriceTick(10, 2000.0), RangePriceTick(11, 2001.0))
        assertTrue(RangeBarsEngine.build("XAUUSD", points, 0.01, 1000, source).isEmpty())
        assertEquals(1, RangeBarsEngine.build("XAUUSD", points, 0.01, 1000, source, true).size)
    }

    @Test fun completedLastRangeDoesNotCreateDuplicateEmptyProjection() {
        val ticks = listOf(RangePriceTick(10, 4000.0), RangePriceTick(11, 4001.0))
        val bars = RangeBarsEngine.build("XAUUSD", ticks, 0.01, 100, source, true)
        assertEquals(1, bars.size)
        assertEquals(4000.0, bars[0].open, 0.0)
        assertEquals(4001.0, bars[0].close, 0.0)
    }

    @Test fun rejectUnsortedInvalidAndLegacyProviderQuotes() {
        assertThrows(IllegalArgumentException::class.java) {
            RangeBarsEngine.build("XAUUSD", listOf(RangePriceTick(2, 1.0),RangePriceTick(1, 2.0)), 0.01, 1000, source)
        }
        assertThrows(IllegalArgumentException::class.java) {
            RangeBarsEngine.build("XAUUSD", listOf(RangePriceTick(1, Double.NaN)), 0.01, 1000, source)
        }
        assertThrows(IllegalArgumentException::class.java) {
            RangeBarsEngine.build("XAUUSD", listOf(RangePriceTick(1, 2000.0)), 0.01, 1000, "OHLC")
        }
    }

    @Test fun rejectRealQuotesThatRequireSmallerTickSizeThanTheHardcodedSymbolStep() {
        val quotes = listOf(RangePriceTick(100, 4050.000), RangePriceTick(101, 4050.005))
        val failure = assertThrows(IllegalArgumentException::class.java) {
            RangeBarsEngine.build("XAUUSD", quotes, 0.01, 100, source)
        }
        assertTrue(failure.message.orEmpty().contains("Tick Size"))
        // These same observed quotes are representable at a genuine 0.001
        // step; the engine is not allowed to round them to a different price.
        val actual = RangeBarsEngine.build("XAUUSD", quotes, 0.001, 100, source, true)
        assertEquals(1, actual.size)
        assertEquals(4050.005, actual.single().close, 0.0)
    }

    @Test fun replayUsesOnlyTicksAtOrBeforeVisibleCutoff() {
        val all = listOf(2000.0, 2010.0, 2020.0).mapIndexed { i, v -> RangePriceTick(100L+i*10, v) }
        val revealed = all.filter { it.timestamp <= 110L }
        val bars = RangeBarsEngine.build("XAUUSD", revealed, 0.01, 1000, source)
        assertEquals(1, bars.size)
        assertEquals(2010.0, bars.single().close, 0.0)
    }
}
