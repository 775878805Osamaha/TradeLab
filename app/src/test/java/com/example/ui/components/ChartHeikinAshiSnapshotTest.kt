package com.example.ui.components

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test

class ChartHeikinAshiSnapshotTest {
    private fun candle(i: Int) = Candle("XAUUSD", Timeframe.M1, i * 60_000L,
        open=100.0+i, high=106.0+i, low=98.0+i, close=104.0+i,
        volume=0.0, closeTime=(i+1)*60_000L, source="TEST_FIXTURE")

    @Test fun knownRecurrencePreservesRawQuotesAndMetadata() = runBlocking {
        val raw = List(3, ::candle)
        val transformed = ChartHeikinAshiSnapshot.prepare(raw).seriesFor(raw)!!.candles
        assertEquals(listOf(102.0,102.0,102.5), transformed.map { it.open })
        assertEquals(listOf(102.0,103.0,104.0), transformed.map { it.close })
        raw.zip(transformed).forEach { (original, display) ->
            assertEquals(original, display.copy(open=original.open, high=original.high,
                low=original.low, close=original.close))
        }
        assertEquals(List(3, ::candle), raw)
    }

    @Test fun scaleIncludesRecursiveOpenBeyondCurrentRawRange() = runBlocking {
        val raw = listOf(candle(0).copy(open=200.0,high=210.0,low=190.0,close=200.0), candle(1))
        val series = ChartHeikinAshiSnapshot.prepare(raw).seriesFor(raw)!!
        assertEquals(200.0, series.candles[1].open, 0.0)
        assertEquals(200.0, series.priceIndex.query(1,2).second, 0.0)
        assertEquals(99.0, series.priceIndex.query(1,2).first, 0.0)
    }

    @Test fun staleResultsCannotMatchPrependLiveRevisionOrEqualCopy() = runBlocking {
        val raw = List(100, ::candle)
        val snapshot = ChartHeikinAshiSnapshot.prepare(raw)
        assertNotNull(snapshot.seriesFor(raw))
        assertNull(snapshot.seriesFor(raw.toList()))
        assertNull(snapshot.seriesFor(listOf(candle(-1)) + raw))
        assertNull(snapshot.seriesFor(raw.dropLast(1)+raw.last().copy(close=150.0)))
        assertNull(snapshot.seriesFor(raw.map { it.copy(symbol="EURUSD") }))
    }

    @Test fun largePreparationReadsOnlyOnWorkerAndHandlesEmptyHistory() = runBlocking {
        val caller=Thread.currentThread()
        val raw=object : AbstractList<Candle>() {
            override val size=100_001
            override fun get(index: Int): Candle {
                check(Thread.currentThread() !== caller)
                return candle(index)
            }
        }
        val series=ChartHeikinAshiSnapshot.prepare(raw).seriesFor(raw)!!
        assertEquals(100_001,series.candles.size)
        val visible=series.candles.subList(99_950,100_001)
        assertEquals(visible.minOf { it.low } to visible.maxOf { it.high },series.priceIndex.query(99_950,100_001))
        val empty=emptyList<Candle>()
        assertTrue(ChartHeikinAshiSnapshot.prepare(empty).seriesFor(empty)!!.candles.isEmpty())
    }

    @Test fun cancellationStopsObsoleteConversionPromptly() = runBlocking {
        val job=Job()
        var reads=0
        val raw=object : AbstractList<Candle>() {
            override val size=100_001
            override fun get(index: Int): Candle {
                if(++reads==3_000) job.cancel()
                return candle(index)
            }
        }
        try {
            withContext(job) { ChartHeikinAshiSnapshot.prepare(raw) }
            fail("Cancelled display transformation must not publish")
        } catch (_: CancellationException) { assertTrue(reads in 3_000..4_097) }
        finally { job.cancel() }
    }
}
