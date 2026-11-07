package com.example.feature.chart.model

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class RangeViewportContinuityTest {
    private val minute = 60_000L

    private fun bars(first: Int, last: Int) = (first..last).map { index ->
        val time = (index + 100) * minute
        Candle(symbol = "XAUUSD", timeframe = Timeframe.M1, openTime = time,
            open = 2000.0, high = 2010.0, low = 1990.0, close = 2004.0,
            source = "ctrader:fixture")
    }

    @Test fun rollingWindowPreservesTheInspectedCandleInsteadOfJumpingToItsNewestBar() {
        val before = bars(1, 80)
        val after = bars(-11, 68)
        val original = 150f
        val shifted = RangeViewportContinuity.offsetAfterWindowChange(
            before, after, 300f, 10f, original)
        assertEquals(30f, shifted, 0.001f)

        val oldViewport = ChartViewport.window(before.size, 300f, 10f, original)
        val newViewport = ChartViewport.window(after.size, 300f, 10f, shifted)
        val oldCenter = before[(oldViewport.startIndex + oldViewport.endIndex - 1) / 2].openTime
        val newCenter = after[(newViewport.startIndex + newViewport.endIndex - 1) / 2].openTime
        assertEquals(oldCenter, newCenter)
    }

    @Test fun jumpingMonthsIntoUnrelatedHistoryResetsViewportToNewPeriod() {
        val previous = bars(400, 480)
        val muchOlder = bars(1, 80)
        assertEquals(0f, RangeViewportContinuity.offsetAfterWindowChange(
            previous, muchOlder, 300f, 10f, 160f), 0f)
    }

    @Test fun growingHistoryToLeftDoesNotAlterPositionOfExistingCandles() {
        val before = bars(20, 80)
        val after = bars(-20, 80)
        assertEquals(130f, RangeViewportContinuity.offsetAfterWindowChange(
            before, after, 300f, 10f, 130f), 0.001f)
    }

    @Test fun sameMillisecondRangeSegmentsPreserveTheExactPriceAnchor() {
        // Five distinct bars share every timestamp, as happens when a single
        // sparse tick creates several visual-only gap segments.
        val before = (0 until 80).map { index ->
            Candle(symbol = "XAUUSD", timeframe = Timeframe.M1,
                openTime = (100L + index / 5) * minute,
                open = 4000.0 + index, high = 4001.0 + index,
                low = 4000.0 + index, close = 4001.0 + index,
                source = "visual-only:range-phantom:ctrader:fixture")
        }
        val earlier = bars(-10, -1)
        val after = earlier + before
        val priorOffset = 150f
        val restoredOffset = RangeViewportContinuity.offsetAfterWindowChange(
            before, after, 300f, 10f, priorOffset)
        assertEquals(priorOffset, restoredOffset, 0.001f)
        val oldViewport = ChartViewport.window(before.size, 300f, 10f, priorOffset)
        val newViewport = ChartViewport.window(after.size, 300f, 10f, restoredOffset)
        val oldCenter = (oldViewport.startIndex + oldViewport.endIndex - 1) / 2
        val newCenter = (newViewport.startIndex + newViewport.endIndex - 1) / 2
        assertEquals(before[oldCenter].open, after[newCenter].open, 0.0)
    }

    @Test fun regroupedRangeCandleFindsObservedQuoteInsideItsTimeSpan() {
        val anchor = Candle("XAUUSD", Timeframe.M1, 20_000L, 20_201L,
            4050.0, 4051.0, 4050.0, 4051.0, source = "ctrader:demo:1:2")
        val regrouped = listOf(
            anchor.copy(openTime = 18_000L, closeTime = 19_000L,
                open = 4040.0, low = 4039.0, high = 4041.0, close = 4041.0),
            anchor.copy(openTime = 19_000L, closeTime = 20_500L,
                open = 4048.0, low = 4048.0, high = 4051.0, close = 4051.0),
            anchor.copy(openTime = 20_001L, closeTime = 22_000L,
                open = 4052.0, low = 4052.0, high = 4053.0, close = 4053.0)
        )
        assertEquals(1, RangeViewportContinuity.findAnchorIndex(regrouped, anchor))
    }

    @Test fun regroupedBarsSharingStartTimeAnchorToClosestPrice() {
        val anchor = Candle("XAUUSD", Timeframe.M1, 1_000L, 1_001L,
            4060.0, 4061.0, 4060.0, 4061.0, source = "ctrader:demo:1:2")
        val regrouped = listOf(anchor.copy(open = 4040.0, high = 4041.0,
                low = 4040.0, close = 4041.0),
            anchor.copy(open = 4060.0, high = 4060.5, low = 4059.0,
                close = 4060.5),
            anchor.copy(open = 4070.0, high = 4071.0, low = 4070.0, close = 4071.0))
        assertEquals(1, RangeViewportContinuity.findAnchorIndex(regrouped, anchor))
    }
}
