package com.example.feature.ctrader

import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class CTraderHistoryPagingTest {
    private val anchor=1_800_000_000_000L

    @Test fun allTimeframesNeverExceedReturnedBarCount() {
        for(timeframe in Timeframe.entries) {
            val window=CTraderHistoryPaging.before(timeframe,anchor)!!
            assertTrue(timeframe.name,window.count in 1..1000)
            assertTrue(timeframe.name,
                (window.to-window.from)/window.sourceInterval+1L<=window.count)
            assertEquals(timeframe.name,anchor-window.sourceInterval,window.to)
            assertTrue(timeframe.name,window.to-window.from<90L*86_400_000L)
        }
    }

    @Test fun consecutiveWindowsNeverSkipARealTradingBar() {
        for(frame in Timeframe.entries) {
            val pages=ArrayList<CTraderHistoryPaging.Window>()
            var exclusive=anchor
            repeat(12) {
                val next=CTraderHistoryPaging.before(frame,exclusive)!!
                pages+=next
                exclusive=next.earlierExclusive()
            }
            for(i in 1 until pages.size) {
                assertEquals(frame.name+" page $i skipped bars",
                    pages[i-1].from-pages[i-1].sourceInterval,pages[i].to)
                assertTrue(pages[i].to<pages[i-1].from)
            }
        }
    }

    @Test fun smallTimeframesCannotJumpAcrossSixDaysAtCount500() {
        for(frame in listOf(Timeframe.M1,Timeframe.M3,Timeframe.M5,Timeframe.M15,Timeframe.M30)) {
            val window=CTraderHistoryPaging.before(frame,anchor,500)!!
            assertTrue(frame.name,window.to-window.from < 500L*frame.minutes*60_000L)
            assertEquals(frame.name,500L,
                (window.to-window.from)/window.sourceInterval+1L)
        }
    }

    @Test fun hourlyPagingNeverSkipsSeveralTradingDaysAtCount500() {
        val first=CTraderHistoryPaging.before(Timeframe.H1,anchor,500)!!
        val second=CTraderHistoryPaging.before(Timeframe.H1,first.from,500)!!
        assertEquals(500L,(first.to-first.from)/3_600_000L+1L)
        assertEquals(first.from-3_600_000L,second.to)
    }

    @Test fun h2BackfillUsesRealH1CountAndNeverSplicesIncompleteBar() {
        val aligned=anchor-anchor%7_200_000L
        val page=CTraderHistoryPaging.before(Timeframe.H2,aligned)!!
        assertEquals("H1",page.sourcePeriod)
        assertEquals(3_600_000L,page.sourceInterval)
        assertEquals(aligned-3_600_000L,page.to)
        assertTrue(page.count<=1000)
        assertTrue((page.to-page.from)/page.sourceInterval+1L <= page.count)
    }

    @Test fun dateBoundaryNearUnixEpochStopsWithoutNegativeRanges() {
        assertNull(CTraderHistoryPaging.before(Timeframe.M15,0L))
        assertNull(CTraderHistoryPaging.before(Timeframe.H1,10L))
        val first=CTraderHistoryPaging.before(Timeframe.M1,60_000L,500)!!
        assertEquals(0L,first.from)
        assertEquals(0L,first.to)
        assertNull(CTraderHistoryPaging.before(Timeframe.M1,first.earlierExclusive(),500))
    }

    @Test fun customCountMatchesExactlyToHistoricalWindowLimit() {
        for(count in listOf(1,2,3,17,100,500,1000)) {
            val w=CTraderHistoryPaging.before(Timeframe.M15,anchor,count)!!
            assertTrue((w.to-w.from)/w.sourceInterval+1L <=count.toLong())
            if(count<=500)assertEquals(count.toLong(),(w.to-w.from)/w.sourceInterval+1L)
        }
    }
}
