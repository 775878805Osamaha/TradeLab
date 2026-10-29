package com.example.core.market

import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class ChartHistorySourceWindowTest {
    private val today=20_000*86_400_000L
    private val boundary=today-ChartHistorySourceWindow.RECENT_DAYS*86_400_000L
    @Test fun crossingPublicationBoundaryLeavesNoUnrequestedIntradaySlots() {
        for(tf in Timeframe.entries.filter { it.minutes<1440 }) {
            val interval=tf.minutes*60_000L
            val from=boundary-10*interval
            val to=boundary+2*interval
            val split=ChartHistorySourceWindow.split(tf,from,to,today+3*interval)
            assertEquals(from,split.archive!!.from)
            assertEquals(boundary-interval,split.archive!!.to)
            assertEquals(boundary,split.recent!!.from)
            assertEquals(to,split.recent!!.to)
            assertEquals(split.archive!!.to+interval,split.recent!!.from)
        }
    }
    @Test fun currentDayUsesRecentHistoryAndCompletedPeriodsUseArchives() {
        val split=ChartHistorySourceWindow.split(Timeframe.M1,today,today+60_000,today+120_000)
        assertNull(split.archive)
        assertEquals(ChartHistorySourceWindow.Window(today,today+60_000),split.recent)
        for(tf in Timeframe.entries) {
            val old=ChartHistorySourceWindow.split(tf,today-10*86_400_000,today-9*86_400_000,today+120_000)
            assertNull(old.recent)
            assertNotNull(old.archive)
        }
    }

    @Test fun yesterdayAndThePublicationLagWindowUseRecentHistoryOnEveryIntradayFrame() {
        for(tf in Timeframe.entries.filter { it.minutes<1440 }) {
            val interval=tf.minutes*60_000L
            val from=today-2*86_400_000L
            val to=today-interval
            val split=ChartHistorySourceWindow.split(tf,from,to,today+3_600_000L)
            assertNull("Yesterday's unpublished file must not become an empty archive for ${tf.code}",split.archive)
            assertEquals(ChartHistorySourceWindow.Window(from,to),split.recent)
        }
    }
}
