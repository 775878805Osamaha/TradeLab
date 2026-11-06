package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class RangePhantomBarsTest {
    private fun real(time: Long, open: Double, close: Double,
                     high: Double = maxOf(open, close),
                     low: Double = minOf(open, close)): Candle = Candle(
        symbol = "XAUUSD", timeframe = Timeframe.M1,
        openTime = time, closeTime = time + 1L,
        open = open, high = high, low = low, close = close,
        source = "ctrader:demo:123:456")

    @Test fun oversizedActualTickJumpBecomesExplicitlyVirtualFixedRangeBodies() {
        val actual = listOf(real(1L, 4060.0, 4050.0))
        val display = RangePhantomBars.project(actual, 0.01, 100)
        assertEquals(10, display.size)
        assertTrue(display.all(RangePhantomBars::isPhantom))
        assertTrue(display.all { kotlin.math.abs(it.open - it.close) <= 1.0000001 })
        assertEquals(4060.0, display.first().open, 1e-8)
        assertEquals(4050.0, display.last().close, 1e-8)
        // The real broker series remains unchanged for Replay and statistics.
        assertEquals(1, actual.size)
        assertEquals(4050.0, actual.single().close, 0.0)
        assertFalse(RangePhantomBars.isPhantom(actual.single()))
    }

    @Test fun priceGapBetweenTrueQuotesGetsOnlyDisplayOnlyPhantoms() {
        val first = real(1L, 2000.0, 2001.0)
        val second = real(2L, 2005.0, 2006.0)
        val display = RangePhantomBars.project(listOf(first, second), 0.01, 100)
        assertEquals(6, display.size)
        assertSame(first, display.first())
        assertSame(second, display.last())
        assertEquals(4, display.count(RangePhantomBars::isPhantom))
        assertEquals(2001.0, display[1].open, 1e-8)
        assertEquals(2005.0, display[4].close, 1e-8)
    }

    @Test fun genuineNonMonotoneWickIsNotReplacedWithImaginaryPath() {
        val spike = real(1L, 2000.0, 1999.0, high = 2010.0, low = 1999.0)
        val display = RangePhantomBars.project(listOf(spike), 0.01, 100)
        assertEquals(listOf(spike), display)
        assertFalse(RangePhantomBars.isPhantom(display.single()))
    }

    @Test fun oversizedBarKeepsItsActualExtremeWicksAfterVisualProjection() {
        val spike = real(1L, 4060.0, 4050.0, high = 4061.5, low = 4049.5)
        val display = RangePhantomBars.project(listOf(spike), 0.01, 100)
        assertEquals(10, display.size)
        assertEquals(4061.5, display.maxOf { it.high }, 1e-8)
        assertEquals(4049.5, display.minOf { it.low }, 1e-8)
        assertTrue(display.all(RangePhantomBars::isPhantom))
    }

    @Test fun smallRealRangeBarIsPreservedVerbatim() {
        val bar = real(1L, 2000.0, 2001.0)
        assertSame(bar, RangePhantomBars.project(listOf(bar), 0.01, 100).single())
    }

    @Test fun phantomBarsNeverAcquireAReplayTimestampBeyondTheVisibleRealQuote() {
        val visible = listOf(real(10L, 2000.0, 2001.0), real(20L, 2010.0, 2011.0))
        val display = RangePhantomBars.project(visible, 0.01, 100)
        assertTrue(display.size > visible.size)
        assertTrue(display.all { it.closeTime <= visible.last().closeTime })
        assertTrue(display.filter(RangePhantomBars::isPhantom).all { it.volume == 0.0 })
    }

    @Test fun extremeBrokenFeedCannotCreateMillionsOfPhantomCandles() {
        val extreme = real(1L, 1.0, 10_000.0)
        assertEquals(listOf(extreme), RangePhantomBars.project(listOf(extreme), 0.01, 100))
    }
}
