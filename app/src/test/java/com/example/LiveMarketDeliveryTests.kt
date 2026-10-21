package com.example

import com.example.core.market.latestMarketFlow
import com.example.core.market.QuoteEndpointPreference
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import org.junit.Assert.*
import org.junit.Test

class LiveMarketDeliveryTests {
    @Test fun busyConsumerReceivesNewestPriceAfterBurst() = runBlocking {
        val prices = latestMarketFlow<Int>()
        val seen = mutableListOf<Int>()
        val release = CompletableDeferred<Unit>()
        val latest = CompletableDeferred<Unit>()
        val collector = launch(start = CoroutineStart.UNDISPATCHED) {
            prices.collect {
                seen.add(it)
                if (it == 1) release.await()
                if (it == 100) latest.complete(Unit)
            }
        }
        try {
            prices.emit(1)
            yield()
            for (price in 2..100) assertTrue(prices.tryEmit(price))
            release.complete(Unit)
            withTimeout(1000) { latest.await() }
            assertEquals(listOf(1, 100), seen)
            assertEquals(listOf(100), prices.replayCache)
        } finally {
            collector.cancelAndJoin()
        }
    }

    @Test fun successfulEndpointIsReusedAndOtherEndpointsRemainAvailable() {
        val preference = QuoteEndpointPreference()
        val original = preference.orderedHosts("BTCUSDT")
        preference.recordSuccess("BTCUSDT", "data-api.binance.vision")
        assertEquals("data-api.binance.vision", preference.orderedHosts("BTCUSDT").first())
        assertEquals(original.toSet(), preference.orderedHosts("BTCUSDT").toSet())
        assertEquals(original.size, preference.orderedHosts("BTCUSDT").size)
        assertEquals(original, preference.orderedHosts("ETHUSDT"))
        preference.recordSuccess("BTCUSDT", "api1.binance.com")
        assertEquals("api1.binance.com", preference.orderedHosts("BTCUSDT").first())
    }
}
