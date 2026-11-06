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
}
