package com.example

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.feature.trade.loadTradeCandles
import java.io.IOException
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class TradeCandleLoaderTests {
    @Test fun goldAndForexUseTheirVerifiedHistoricalProvider() = runBlocking {
        for (symbol in listOf("XAUUSD", "EURUSD", "GBPUSD")) {
            var requested = false
            val candles = listOf(Candle(symbol = symbol, timeframe = Timeframe.M15,
                openTime = 60000L, open = 100.0, high = 102.0, low = 99.0, close = 101.0))
            val result = loadTradeCandles(symbol) { requested = true; candles }
            assertTrue(requested)
            assertEquals(candles, result.candles)
            assertNull(result.message)
        }
    }

    @Test fun emptyProviderResponseShowsRetryableMessage() = runBlocking {
        val result = loadTradeCandles("BTCUSDT") { emptyList() }
        assertTrue(result.candles.isEmpty())
        assertNotNull(result.message)
        assertTrue(result.message!!.contains("BTCUSDT"))
        assertTrue(result.message!!.contains("إعادة المحاولة"))
    }

    @Test fun networkFailureIsRecoverableAndNextLoadSucceeds() = runBlocking {
        val failed = loadTradeCandles("BTCUSDT") { throw IOException("offline") }
        assertTrue(failed.candles.isEmpty())
        assertNotNull(failed.message)
        assertTrue(failed.message!!.contains("IOException"))
        assertTrue(failed.message!!.contains("offline"))
        val candles = listOf(Candle(symbol = "BTCUSDT", timeframe = Timeframe.M15,
            openTime = 0L, open = 100.0, high = 102.0, low = 99.0, close = 101.0, volume = 1.0))
        val recovered = loadTradeCandles("BTCUSDT") { candles }
        assertEquals(candles, recovered.candles)
        assertNull(recovered.message)
    }

    @Test fun cancellationIsNotConvertedToNetworkFailure() = runBlocking {
        val cancellation = CancellationException("symbol changed")
        try {
            loadTradeCandles("ETHUSDT") { throw cancellation }
            fail("Cancellation must propagate")
        } catch (actual: CancellationException) {
            assertSame(cancellation, actual)
        }
    }

    @Test fun cancelledProviderReturningLateCannotPublish() = runBlocking {
        var published = false
        val request = launch(start = CoroutineStart.UNDISPATCHED) {
            loadTradeCandles("BTCUSDT") {
                currentCoroutineContext().cancel()
                emptyList()
            }
            published = true
        }
        request.join()
        assertTrue(request.isCancelled)
        assertFalse(published)
    }
}
