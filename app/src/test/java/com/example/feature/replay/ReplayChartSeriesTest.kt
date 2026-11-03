package com.example.feature.replay

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class ReplayChartSeriesTest {
    private val t=Timeframe.M15.minutes*60_000L
    private fun candle(index:Int) = Candle("XAUUSD",Timeframe.M15,1_700_000_000_000L+index*t,
        open=2000.0,high=2002.0,low=1998.0,close=2001.0,
        source="CTRADER_HISTORICAL")

    @Test fun largeHistoryIsIndexedWithoutCopyingEachCandle() {
        val older=List(100_000) { candle(it) }
        val revealed=List(20) { candle(100_000+it) }
        val series=ReplayChartSeries(older,revealed)
        assertEquals(100_020,series.size)
        assertSame(older.first(),series[0])
        assertSame(older.last(),series[99_999])
        assertSame(revealed.first(),series[100_000])
        assertSame(revealed.last(),series.last())
        assertEquals(listOf(older[99_998],older[99_999],revealed.first()),
            series.subList(99_998,100_001))
        assertThrows(IndexOutOfBoundsException::class.java) { series[-1] }
        assertThrows(IndexOutOfBoundsException::class.java) { series[100_020] }
    }

    @Test fun extendingVisibleReplayDoesNotMutatePreviouslyPublishedFrame() {
        val older=listOf(candle(1),candle(2))
        val before=ReplayChartSeries(older,listOf(candle(3)))
        val after=ReplayChartSeries(older,listOf(candle(3),candle(4)))
        assertEquals(3,before.size)
        assertEquals(4,after.size)
        assertEquals(candle(3).openTime,before.last().openTime)
    }

    @Test fun missingFutureIsNeverSynthesizedInChartSeries() {
        val data=ReplayChartSeries(listOf(candle(0)),listOf(candle(1),candle(2)))
        assertEquals(3,data.size)
        assertFalse(data.any { it.openTime>=candle(3).openTime })
    }
}
