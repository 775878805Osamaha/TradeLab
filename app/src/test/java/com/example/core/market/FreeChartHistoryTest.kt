package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class FreeChartHistoryTest {
    private val bars=listOf(Candle("XAUUSD",Timeframe.M1,60_000,
        open=100.0,high=102.0,low=99.0,close=101.0,source="TEST_FIXTURE"))
    @Test fun verifiedSparseCacheAvoidsTheFailingNetwork() = runBlocking {
        for(cached in listOf(bars,emptyList())) {
            val actual=FreeChartHistory.load({cached},{fail("Cache must avoid primary");emptyList()},
                {fail("Cache must avoid download");emptyList()})
            assertSame(cached,actual)
        }
    }
    @Test fun unavailableOrEmptyPrimaryUsesIndependentFreeSource() = runBlocking {
        for(message in listOf("Historical archive HTTP 503","Historical archive network failure")) {
            var calls=0
            assertSame(bars,FreeChartHistory.load({null},{throw MarketDataRequestException(message)},{calls++;bars}))
            assertEquals(1,calls)
        }
        assertSame(bars,FreeChartHistory.load({null},{emptyList()},{bars}))
    }
    @Test fun rateLimitsMalformedDataAndCancellationAreNeverHidden() = runBlocking {
        for(error in listOf(MarketDataRequestException("HTTP 429"),MarketDataRequestException("HTTP 403"),
            IllegalArgumentException("Invalid prices"),CancellationException("stop"))) {
            try {
                FreeChartHistory.load({null},{throw error},{fail("Must not mask this failure");bars})
                fail()
            } catch(actual: Exception) { assertSame(error,actual) }
        }
    }
}
