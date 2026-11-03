package com.example.feature.ctrader

import org.junit.Assert.*
import org.junit.Test

class CTraderHistoricalPageCacheTest {
    private fun key(account:String="a",symbol:Long=51,period:String="M15",start:Long=1000L) =
        CTraderHistoricalPageCache.Key(account,symbol,period,start,start+900_000L,500)
    private fun bars(open:Double)=listOf(
        CTraderReadOnlyMarketApi.BrokerCandle(1_700_000_000_000L,open,open+3.0,open-2.0,open+1.0,7)
    )

    @Test fun brokerAccountsNeverShareTheSameXauusdHistory() {
        val cache=CTraderHistoricalPageCache(10)
        cache.put(key("demo"),bars(4000.0))
        assertNull(cache.get(key("live")))
        cache.put(key("live"),bars(4100.0))
        assertEquals(4000.0,cache.get(key("demo"))!!.single().open,0.0)
        assertEquals(4100.0,cache.get(key("live"))!!.single().open,0.0)
    }

    @Test fun brokerSymbolIdsAndPeriodsAreIsolated() {
        val cache=CTraderHistoricalPageCache(10)
        cache.put(key(symbol=51),bars(4000.0))
        assertNull(cache.get(key(symbol=52)))
        assertNull(cache.get(key(period="H1")))
        assertNull(cache.get(key(start=500L)))
    }

    @Test fun oldestPageEvictsWithoutDisruptingRecentlyAccessedPage() {
        val cache=CTraderHistoricalPageCache(2)
        cache.put(key(start=1),bars(1.0))
        cache.put(key(start=2),bars(2.0))
        assertNotNull(cache.get(key(start=1)))
        cache.put(key(start=3),bars(3.0))
        assertNull(cache.get(key(start=2)))
        assertNotNull(cache.get(key(start=1)))
        assertNotNull(cache.get(key(start=3)))
        assertEquals(2,cache.size())
    }

    @Test fun logoutClearsAllPageData() {
        val cache=CTraderHistoricalPageCache(4)
        cache.put(key("a"),bars(4000.0))
        cache.put(key("b"),bars(4010.0))
        cache.clear()
        assertEquals(0,cache.size())
        assertNull(cache.get(key("a")))
        assertNull(cache.get(key("b")))
    }

    @Test fun insertedListIsCopiedToAvoidNetworkResponseMutation() {
        val cache=CTraderHistoricalPageCache(4)
        val raw=bars(4000.0).toMutableList()
        cache.put(key(),raw)
        raw.clear()
        assertEquals(1,cache.get(key())!!.size)
    }

    @Test fun invalidEntriesAreRejectedBeforeCaching() {
        assertThrows(IllegalArgumentException::class.java) {
            CTraderHistoricalPageCache.Key("",1,"M15",100,200,500)
        }
        assertThrows(IllegalArgumentException::class.java) {
            CTraderHistoricalPageCache.Key("account",1,"M15",200,100,500)
        }
        assertThrows(IllegalArgumentException::class.java) {
            CTraderHistoricalPageCache.Key("account",1,"M15",100,200,1001)
        }
    }
}
