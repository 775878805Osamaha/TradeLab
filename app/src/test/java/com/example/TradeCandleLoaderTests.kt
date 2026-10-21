package com.example

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.feature.trade.loadTradeCandles
import java.io.IOException
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class TradeCandleLoaderTests {
    @Test fun unsupportedSymbolsNeverCallProvider() = runBlocking {
        for (symbol in listOf("XAUUSD", "EURUSD", "GBPUSD")) {
            val result = loadTradeCandles(symbol) { error("Unsupported provider called") }
            assertTrue(result.candles.isEmpty())
            assertTrue(result.message!!.contains(symbol))
        }
    }

    @Test fun networkFailureIsRecoverableAndNextLoadSucceeds() = runBlocking {
        val failed = loadTradeCandles("BTCUSDT") { throw IOException("offline") }
        assertTrue(failed.candles.isEmpty())
        assertNotNull(failed.message)
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
