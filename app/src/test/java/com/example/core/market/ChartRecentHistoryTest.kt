package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class ChartRecentHistoryTest {
    private val today=20_000*86_400_000L
    private val tf=Timeframe.M15
    private val interval=900_000L
    private fun bar(time: Long)=Candle("XAUUSD",tf,time,open=100.0,high=101.0,low=99.0,
        close=100.0,volume=0.0,closeTime=time+interval,source="TEST_FIXTURE")

    @Test fun anActualRecentPageIsKeptWithoutUnnecessaryArchiveWork() = runBlocking {
        val page=listOf(bar(today-interval))
        val result=ChartRecentHistory.load(tf,today-2*86_400_000L,today-interval,today+interval,
            recent={page},archive={_,_ -> fail("A real page already advances the cursor");emptyList()})
        assertSame(page,result)
    }

    @Test fun exhaustedRecentRetentionTriesCompletedArchiveSlots() = runBlocking {
        for(noHistory in listOf(false,true)) {
            var archived=0
            val from=today-2*86_400_000L
            val result=ChartRecentHistory.load(tf,from,today+interval,today+2*interval,
                recent={if(noHistory) throw NoHistoricalCandlesException("XAUUSD") else emptyList()},
                archive={start,end -> archived++;assertEquals(from,start);assertEquals(today-interval,end);listOf(bar(end))})
            assertEquals(1,archived)
            assertEquals(today-interval,result.single().openTime)
        }
    }

    @Test fun anUnpublishedCurrentDayIsNeverRequestedFromCompletedArchives() = runBlocking {
        val result=ChartRecentHistory.load(tf,today,today+interval,today+2*interval,
            recent={emptyList()},archive={_,_ -> fail("No completed day is covered");emptyList()})
        assertTrue(result.isEmpty())
    }

    @Test fun quotasNetworkErrorsAndCancellationAreNotTreatedAsExhaustedRetention() = runBlocking {
        for(failure in listOf(MarketDataRequestException("HTTP 429"),MarketDataRequestException("network failure"),
            IOException("Invalid OHLC"),CancellationException("stop"))) {
            try {
                ChartRecentHistory.load(tf,today-86_400_000L,today-interval,today,
                    recent={throw failure},archive={_,_ -> fail("Failure is not empty history");emptyList()})
                fail()
            } catch(actual: Exception) { assertSame(failure,actual) }
        }
    }
}
