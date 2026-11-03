package com.example.feature.replay

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class ReplayHistoricalPagesTest {
    private val step=Timeframe.M15.minutes*60_000L
    private val anchor=1_900_000L*step
    private fun bar(i:Int)=Candle("XAUUSD",Timeframe.M15,anchor+i*step,
        open=2000.0,high=2001.0,low=1999.0,close=2000.5,volume=2.0,
        source="CTRADER_HISTORICAL")

    @Test fun oneHundredThousandRealLookbackBarsRemainIndexableAcrossTwoHundredPages() {
        var history:List<Candle> = emptyList()
        val firstPage=List(500){bar(-500+it)}
        history=ReplayChartLookback.prepend(history,firstPage,anchor,
            "XAUUSD",Timeframe.M15)
        val originalLast=history.last()
        for(batch in 1 until 200) {
            val older=List(500){i->bar(-(batch+1)*500+i)}
            history=ReplayChartLookback.prepend(history,older,anchor,
                "XAUUSD",Timeframe.M15)
        }
        assertTrue(history is ReplayHistoricalPages)
        assertEquals(100_000,history.size)
        assertSame(originalLast,history.last())
        assertEquals(bar(-100_000).openTime,history.first().openTime)
        assertEquals(bar(-500).openTime,history[99_500].openTime)
        assertEquals(bar(-1).openTime,history.last().openTime)
        assertEquals(21,ReplayChartSeries(history,List(21){bar(it)}).size-100_000)
    }

    @Test fun crossSessionBoundaryOrTimeframeIsRejectedBeforeMerge() {
        val old=ReplayChartLookback.prepend(emptyList(),listOf(bar(-2),bar(-1)),
            anchor,"XAUUSD",Timeframe.M15)
        for(boundary in listOf(anchor-step,anchor+step)) {
            val error=assertThrows(ReplayChartLookback.InvalidPage::class.java) {
                ReplayChartLookback.prepend(old,listOf(bar(-3)),boundary,
                    "XAUUSD",Timeframe.M15)
            }
            assertEquals(ReplayChartLookback.Reason.SOURCE,error.reason)
        }
    }

    @Test fun chunkedHistorySupportsRandomAccessAndSublistBounds() {
        val one=ReplayChartLookback.prepend(emptyList(),listOf(bar(-5),bar(-4)),
            anchor,"XAUUSD",Timeframe.M15)
        val two=ReplayChartLookback.prepend(one,listOf(bar(-8),bar(-7),bar(-6)),
            anchor,"XAUUSD",Timeframe.M15)
        assertEquals(listOf(-8,-7,-6,-5,-4).map { bar(it).openTime },
            two.map { it.openTime })
        assertEquals(listOf(bar(-6),bar(-5)),two.subList(2,4))
        assertThrows(IndexOutOfBoundsException::class.java){two[-1]}
        assertThrows(IndexOutOfBoundsException::class.java){two[two.size]}
    }
}
