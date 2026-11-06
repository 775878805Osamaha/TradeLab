package com.example.core.market

import org.junit.Assert.*
import org.junit.Test

class RangeBarsEngineTest {
    private val source = "ctrader:demo:123:456"

    @Test fun fixedThousandPriceTicksBuildActualGoldRanges() {
        val points = listOf(2000.0, 2004.0, 2010.0, 2010.5, 2008.0, 1999.5)
            .mapIndexed { i, price -> RangePriceTick(1_000L + i * 1000, price) }
        val bars = RangeBarsEngine.build("XAUUSD", points, 0.01, 1000, source)
        assertEquals(2, bars.size)
        assertEquals(2000.0, bars[0].open, 0.0)
        assertEquals(2010.0, bars[0].close, 0.0)
        assertEquals(2010.5, bars[1].open, 0.0)
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

    @Test fun unfinishedBarIsHiddenInReplayButVisibleInAnalysis() {
        val points = listOf(RangePriceTick(10, 2000.0), RangePriceTick(11, 2001.0))
        assertTrue(RangeBarsEngine.build("XAUUSD", points, 0.01, 1000, source).isEmpty())
        assertEquals(1, RangeBarsEngine.build("XAUUSD", points, 0.01, 1000, source, true).size)
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

    @Test fun replayUsesOnlyTicksAtOrBeforeVisibleCutoff() {
        val all = listOf(2000.0, 2010.0, 2020.0).mapIndexed { i, v -> RangePriceTick(100L+i*10, v) }
        val revealed = all.filter { it.timestamp <= 110L }
        val bars = RangeBarsEngine.build("XAUUSD", revealed, 0.01, 1000, source)
        assertEquals(1, bars.size)
        assertEquals(2010.0, bars.single().close, 0.0)
    }
}
