package com.example

import com.example.core.history.HistoryError
import com.example.core.history.TwelveDataHistory
import com.example.core.model.Timeframe
import kotlinx.coroutines.runBlocking
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.IOException
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = android.app.Application::class)
class TwelveDataHistoryTests {
    @get:Rule val temp = TemporaryFolder()
    private val start = Instant.parse("2026-01-05T00:00:00Z").toEpochMilli()
    private fun body(symbol: String = "XAU/USD", interval: String = "1min", rows: String = row()) =
        """{"meta":{"symbol":"$symbol","interval":"$interval"},"values":[$rows],"status":"ok"}"""
    private fun row(time: String = "2026-01-05 00:00:00", low: String = "1999") =
        """{"datetime":"$time","open":"2000","high":"2002","low":"$low","close":"2001"}"""

    @Test fun parsesRealOhlcWithoutInventingVolumeOrMissingBars() {
        val candles = TwelveDataHistory.parse(body(rows = row("2026-01-05 00:02:00") + "," + row()),
            "XAUUSD", Timeframe.M1, start, start + 180000)
        assertEquals(listOf(start, start + 120000), candles.map { it.openTime })
        assertEquals(0.0, candles[0].volume, 0.0)
        assertEquals("TWELVE_DATA_HISTORICAL", candles[0].source)
        assertEquals(2001.0, candles[0].close, 0.0)
    }

    @Test fun rejectsWrongSymbolIntervalInvalidPricesDuplicatesAndUnfinishedBars() {
        val invalid = listOf(body(symbol = "EUR/USD"), body(interval = "5min"),
            body(rows = row(low = "2005")), body(rows = row() + "," + row()),
            body(rows = row("2026-01-05 00:01:00")), """{"status":"error","code":429}""")
        for (payload in invalid) {
            assertThrows(Exception::class.java) {
                TwelveDataHistory.parse(payload, "XAUUSD", Timeframe.M1, start, start + 60000)
            }
        }
    }

    @Test fun cachedRangeWorksOfflineWithoutKeyAndUsesUtcParameters() = runBlocking {
        var requests = 0
        var key = "test-key"
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            assertEquals("XAU/USD", chain.request().url.queryParameter("symbol"))
            assertEquals("UTC", chain.request().url.queryParameter("timezone"))
            assertEquals("1min", chain.request().url.queryParameter("interval"))
            assertEquals("1000", chain.request().url.queryParameter("outputsize"))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200)
                .message("OK").body(body().toResponseBody("application/json".toMediaType())).build()
        }.build()
        val directory = temp.newFolder()
        val loader = TwelveDataHistory({ key }, directory, { it.name }, client, { start + 60000 })
        val first = loader.load("XAUUSD", Timeframe.M1, start, start + 60000)
        key = ""
        val second = loader.load("XAUUSD", Timeframe.M1, start, start + 60000)
        assertEquals(first, second)
        assertEquals(1, requests)
    }

    @Test fun missingKeyAndUnsupportedIntervalFailBeforeNetwork() = runBlocking {
        val loader = TwelveDataHistory({ "" }, temp.newFolder(), { it.name }, clock = { start + 60000 })
        try { loader.load("XAUUSD", Timeframe.M1, start, start + 60000); fail() }
        catch (error: IOException) { assertEquals(HistoryError.KEY.name, error.message) }
        try { loader.load("XAUUSD", Timeframe.M3, start, start + 60000); fail() }
        catch (error: IOException) { assertEquals(HistoryError.INTERVAL.name, error.message) }
    }

    @Test fun providerErrorIsNotCachedOrReturnedAsEmptySuccess() = runBlocking {
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200)
                .message("OK").body("""{"status":"error","code":429,"message":"private detail"}"""
                    .toResponseBody("application/json".toMediaType())).build()
        }.build()
        val directory = temp.newFolder()
        val loader = TwelveDataHistory({ "test-key" }, directory, { it.name }, client, { start + 60000 })
        try { loader.load("XAUUSD", Timeframe.M1, start, start + 60000); fail() }
        catch (error: IOException) { assertEquals(HistoryError.LIMIT.name, error.message) }
        assertTrue(directory.listFiles()!!.isEmpty())
    }
}
