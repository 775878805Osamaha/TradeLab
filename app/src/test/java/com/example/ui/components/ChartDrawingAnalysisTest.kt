package com.example.ui.components

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.feature.chart.model.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test

class ChartDrawingAnalysisTest {
    private fun candle(i: Int, volume: Double = 2.0) = Candle("XAUUSD",Timeframe.M1,(i+1)*60_000L,
        open=100.0,high=100.0,low=100.0,close=100.0,volume=volume,source="TEST_FIXTURE")
    private fun drawings(end: Long) = listOf(
        ChartDrawing(id=1,tool=DrawingTool.ANCHORED_VWAP,symbol="XAUUSD",timeframe="M1",startPrice=100.0,startTime=60_000L),
        ChartDrawing(id=2,tool=DrawingTool.VOLUME_PROFILE_FIXED,symbol="XAUUSD",timeframe="M1",startPrice=100.0,startTime=60_000L,endTime=end)
    )

    @Test fun largeAnalysisReadsHistoryOffTheCallingThreadAndPreservesRealWeights() = runBlocking {
        val caller=Thread.currentThread()
        val bars=object : AbstractList<Candle>() {
            override val size=100_001
            override fun get(index: Int): Candle {
                check(Thread.currentThread() !== caller) { "Analysis scanned history on the UI caller" }
                return candle(index)
            }
        }
        val request=ChartDrawingAnalysisRequest(bars,drawings(100_001*60_000L))
        val result=ChartDrawingAnalysisSnapshot.prepare(request)
        assertTrue(result.matches(request))
        assertEquals(100_001,result.vwaps[1L]!!.size)
        assertEquals(100.0,result.vwaps[1L]!!.last().price,0.0)
        assertEquals(listOf(CandleVolumeProfile.Bin(100.0,200_002.0)),result.profiles[2L])
    }

    @Test fun chartsWithoutAnalysisToolsNeverScanHistory() = runBlocking {
        val bars=object : AbstractList<Candle>() {
            override val size=100_001
            override fun get(index: Int): Candle = error("No analysis tool should read OHLC")
        }
        val ordinary=drawings(600_000).first().copy(tool=DrawingTool.HORIZONTAL_LINE)
        val request=ChartDrawingAnalysisRequest(bars,listOf(ordinary))
        assertTrue(request.isEmpty)
        val result=ChartDrawingAnalysisSnapshot.prepare(request)
        assertTrue(result.vwaps.isEmpty());assertTrue(result.profiles.isEmpty())
    }

    @Test fun anchorEditsAndNewSeriesRejectOldResultsWhileStyleEditsReuseThem() = runBlocking {
        val bars=List(100) { candle(it) }
        val tools=drawings(bars.last().openTime)
        val result=ChartDrawingAnalysisSnapshot.prepare(ChartDrawingAnalysisRequest(bars,tools))
        assertFalse(result.matches(ChartDrawingAnalysisRequest(bars.toList(),tools)))
        assertFalse(result.matches(ChartDrawingAnalysisRequest(bars,tools.map { it.copy(startTime=120_000L) })))
        assertFalse(result.matches(ChartDrawingAnalysisRequest(bars,emptyList())))
        assertTrue(result.matches(ChartDrawingAnalysisRequest(bars,tools.map { it.copy(strokeWidth=5f,text="style edit") })))
    }

    @Test fun cancelledAnalysisStopsBeforeScanningTheWholeSeries() = runBlocking {
        val job=Job();var reads=0
        val bars=object : AbstractList<Candle>() {
            override val size=100_001
            override fun get(index: Int): Candle {
                if(++reads==3_000) job.cancel()
                return candle(index)
            }
        }
        try {
            withContext(job) { ChartDrawingAnalysisSnapshot.prepare(ChartDrawingAnalysisRequest(bars,drawings(6_000_000L))) }
            fail("Cancelled results must never be published")
        } catch (_: CancellationException) { assertTrue("reads=$reads",reads in 3_000..4_096) }
        finally { job.cancel() }
    }

    @Test fun unavailableVolumeProducesKnownEmptyResultsWithoutFabrication() = runBlocking {
        val bars=List(100) { candle(it,0.0) }
        val result=ChartDrawingAnalysisSnapshot.prepare(ChartDrawingAnalysisRequest(bars,drawings(bars.last().openTime)))
        assertTrue(result.vwaps.containsKey(1L));assertTrue(result.vwaps[1L]!!.isEmpty())
        assertTrue(result.profiles.containsKey(2L));assertTrue(result.profiles[2L]!!.isEmpty())
    }

    @Test fun replayRewindCannotReuseAnalysisContainingFuturePoints() = runBlocking {
        val full=List(100) { candle(it) }
        val tools=drawings(full.last().openTime)
        val previous=ChartDrawingAnalysisSnapshot.prepare(ChartDrawingAnalysisRequest(full,tools))
        val revealed=full.take(40)
        val request=ChartDrawingAnalysisRequest(revealed,tools)
        assertFalse(previous.matches(request))
        val rewound=ChartDrawingAnalysisSnapshot.prepare(request)
        assertEquals(40,rewound.vwaps[1L]!!.size)
        assertTrue(rewound.vwaps[1L]!!.all { it.time<=revealed.last().openTime })
        assertEquals(80.0,rewound.profiles[2L]!!.sumOf { it.volume },0.0)
    }

    @Test fun sessionProfileExcludesAdjacentDaysAndRejectsNonPositiveVolume() {
        val day=86_400_000L
        val tools=drawings(day).last().copy(tool=DrawingTool.VOLUME_PROFILE_SESSION,startTime=day+60_000L)
        val bars=listOf(candle(0,100.0).copy(openTime=day-60_000L),
            candle(1,2.0).copy(openTime=day),candle(2,6.0).copy(openTime=day+60_000L,close=120.0,high=120.0),
            candle(3,0.0).copy(openTime=day+120_000L),candle(4,-1.0).copy(openTime=day+180_000L),
            candle(5,100.0).copy(openTime=2*day))
        val bins=CandleVolumeProfile.forDrawing(bars,tools)
        assertEquals(8.0,bins.sumOf { it.volume },0.0)
        assertEquals(100.5,bins.first().price,0.0)
        assertEquals(119.5,bins.last().price,0.0)
    }
}
