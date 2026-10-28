package com.example.core.market

import com.example.core.model.Timeframe
import kotlinx.coroutines.runBlocking
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = android.app.Application::class)
class TwelveDataHistoricalProviderTest {
    private val start = Instant.parse("2025-04-30T00:00:00Z").toEpochMilli()
    private fun client(check: (Request) -> Unit = {}, payload: String): OkHttpClient =
        OkHttpClient.Builder().addInterceptor { chain ->
            check(chain.request())
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("Fixture")
                .body(payload.toResponseBody()).build()
        }.build()

    @Test fun threeMinuteCandlesIncludeTheLastSourceMinuteAndKeepActualSessionGaps() = runBlocking {
        val rows = listOf(0,1,2,6,7,8).reversed().joinToString(",") { minute ->
            """{"datetime":"2025-04-30 00:0$minute:00","open":"${2000+minute}","high":"${2010+minute}","low":"1990","close":"${2001+minute}","volume":"2"}"""
        }
        val payload = """{"meta":{"symbol":"XAU/USD","interval":"1min"},"values":[$rows],"status":"ok"}"""
        val provider = TwelveDataHistoricalProvider(client({ request ->
            assertEquals("1min", request.url.queryParameter("interval"))
            assertEquals("2025-04-30T00:08:00", request.url.queryParameter("end_date"))
            assertEquals("UTC", request.url.queryParameter("timezone"))
        }, payload))
        val bars = provider.fetch("XAUUSD",Timeframe.M3,start,start+360_000,"fixture-key")
        assertEquals(listOf(start,start+360_000),bars.map { it.openTime })
        assertEquals(2000.0,bars.first().open,0.0)
        assertEquals(2012.0,bars.first().high,0.0)
        assertEquals(2003.0,bars.first().close,0.0)
        assertEquals(6.0,bars.first().volume,0.0)
        assertTrue(bars.all { it.timeframe==Timeframe.M3 && it.source=="TWELVE_DATA_HISTORICAL" })
    }

    @Test fun threeMinuteSourceLimitAndAlignmentFailBeforeNetwork() = runBlocking {
        val provider = TwelveDataHistoricalProvider(client({ fail("Unexpected network request") }, ""))
        for ((from,to) in listOf(start to start+1666*180_000L, start+60_000 to start+180_000)) {
            try { provider.fetch("XAUUSD",Timeframe.M3,from,to,"fixture-key"); fail() }
            catch (_: IllegalArgumentException) { }
        }
    }

    @Test fun quotaErrorIsTerminalAndDoesNotExposeProviderPayloadOrKey() = runBlocking {
        val provider = TwelveDataHistoricalProvider(client(payload="""{"status":"error","code":429,"message":"private fixture-key detail"}"""))
        try { provider.fetch("XAUUSD",Timeframe.M3,start,start,"fixture-key"); fail() }
        catch (error: MarketDataRequestException) {
            assertFalse(error.toString().contains("fixture-key"))
            assertFalse(error.toString().contains("private"))
        }
    }
}
