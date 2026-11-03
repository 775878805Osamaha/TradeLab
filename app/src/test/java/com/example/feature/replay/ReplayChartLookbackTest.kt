package com.example.feature.replay

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.core.replay.HistoricalReplayEngine
import com.example.feature.ctrader.CTraderHistoryPaging
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class ReplayChartLookbackTest {
    private val interval=Timeframe.M15.minutes*60_000L
    private val anchor=interval*1_000_000L
    private fun bar(step:Long,source:String="CTRADER_HISTORICAL",symbol:String="XAUUSD")=
        Candle(symbol,Timeframe.M15,anchor+step*interval,
            open=2500.0+step,high=2502.0+step,low=2499.0+step,
            close=2501.0+step,volume=10.0,source=source)

    @Test fun olderBrokerPagesPrependWithoutExposingAnyFutureReplayBars() {
        val initial=List(30) { bar(it.toLong()) }
        val replay=HistoricalReplayEngine()
        replay.initialize(initial,20)
        assertEquals(21,replay.visibleCandles.value.size)
        val old=ReplayChartLookback.prepend(emptyList(),List(10) { bar(it.toLong()-10) },
            initial.first().openTime,"XAUUSD",Timeframe.M15)
        val allOnChart=old+replay.visibleCandles.value
        assertEquals(31,allOnChart.size)
        assertEquals("CTRADER_HISTORICAL",allOnChart.first().source)
        assertEquals(21,replay.visibleCandles.value.size)
        assertEquals(30,replay.totalCandles.value)
        assertEquals(20,replay.currentIndex.value)
        assertEquals(initial.first().openTime,replay.snapshotCandles().first().openTime)
        assertFalse(allOnChart.any { it.openTime > replay.currentCandle.value!!.openTime })
    }

    @Test fun repetitivePagingMergesSortedDistinctBarsWithoutAnArtificialOffsetCeiling() {
        val first=ReplayChartLookback.prepend(emptyList(),listOf(bar(-2),bar(-1)),
            anchor,"XAUUSD",Timeframe.M15)
        val second=ReplayChartLookback.prepend(first,listOf(bar(-4),bar(-3)),
            anchor,"XAUUSD",Timeframe.M15)
        assertEquals(4,second.size)
        assertEquals(listOf(-4L,-3L,-2L,-1L).map { anchor+it*interval },
            second.map { it.openTime })
    }

    @Test fun rejectedIfOldBrokerOrFutureCandleWouldLeakIntoReplay() {
        val valid=bar(-1)
        for (unauthorized in listOf(
            valid.copy(source="BIQUOTE_HISTORICAL"),
            valid.copy(source="TWELVE_DATA_HISTORICAL"),
            valid.copy(source="BINANCE_HISTORICAL"),
            bar(1)
        )) {
            assertThrows(IOException::class.java) {
                ReplayChartLookback.prepend(emptyList(),listOf(unauthorized),anchor,
                    "XAUUSD",Timeframe.M15)
            }
        }
    }

    @Test fun binanceCacheBarsAreAllowedOnlyForCrypto() {
        val earliest=anchor
        val old=bar(-1,"BINANCE_HISTORICAL_CACHED","BTCUSDT")
        assertEquals(1,ReplayChartLookback.prepend(emptyList(),listOf(old),
            earliest,"BTCUSDT",Timeframe.M15).size)
        assertThrows(IOException::class.java) {
            ReplayChartLookback.prepend(emptyList(),listOf(old),earliest,
                "XAUUSD",Timeframe.M15)
        }
    }

    @Test fun brokerBackfillWindowsStayBelow90DayGatewayCap() {
        for(frame in Timeframe.entries) {
            assertTrue(frame.toString(),CTraderHistoryPaging.windowSpan(frame)>0)
            assertTrue(frame.toString(),
                CTraderHistoryPaging.windowSpan(frame)<=89L*86_400_000L)
        }
    }
}
