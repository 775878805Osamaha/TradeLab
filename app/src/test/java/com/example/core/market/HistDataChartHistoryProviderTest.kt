package com.example.core.market

import com.example.core.model.Timeframe
import kotlinx.coroutines.runBlocking
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Synthetic transport fixtures. Actual free-source scale is checked on Android. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28],application=android.app.Application::class)
class HistDataChartHistoryProviderTest {
    @get:Rule val temp=TemporaryFolder()
    private val start=Instant.parse("2025-01-06T05:00:00Z").toEpochMilli()
    private fun row(date: String="20250106 000000",close: String="2001")="$date;2000;2010;1990;$close;0"
    private fun zip(rows: String,year: Int=2025): ByteArray {
        val out=ByteArrayOutputStream()
        ZipOutputStream(out).use { z ->
            z.putNextEntry(ZipEntry("DAT_ASCII_XAUUSD_M1_$year.csv"));z.write(rows.toByteArray());z.closeEntry()
        }
        return out.toByteArray()
    }
    private fun file(bytes: ByteArray)=temp.newFile().also { it.writeBytes(bytes) }
    private fun form(year: Int=2025,action: String="/get.php")="""<form id="file_down" method="POST" action="$action">
        <input type="hidden" name="tk" value="0123456789abcdef0123456789abcdef">
        <input type="hidden" name="date" value="$year"><input type="hidden" name="datemonth" value="$year">
        <input type="hidden" name="platform" value="ASCII"><input type="hidden" name="timeframe" value="M1">
        <input type="hidden" name="fxpair" value="XAUUSD"></form>"""

    @Test fun anonymousPublicDownloadIsCachedAndReusedWithoutNetwork() = runBlocking {
        var requests=0
        val client=OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            val request=chain.request()
            val body=if(request.method=="GET") {
                assertTrue(request.url.toString().endsWith("/xauusd/2025"));form().toByteArray()
            } else {
                assertEquals("/get.php",request.url.encodedPath)
                assertTrue(request.header("Referer")!!.endsWith("/xauusd/2025"))
                val fields=request.body as FormBody
                assertEquals("2025",(0 until fields.size).associate { fields.name(it) to fields.value(it) }["datemonth"])
                zip(row())
            }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("Fixture").body(body.toResponseBody()).build()
        }.build()
        val directory=temp.newFolder()
        val bars=HistDataChartHistoryProvider(directory,client).fetch("XAUUSD",Timeframe.M1,start,start)
        assertEquals(2001.0,bars.single().close,0.0)
        val offline=OkHttpClient.Builder().addInterceptor { fail("Must use cached data");throw java.io.IOException() }.build()
        assertEquals(bars,HistDataChartHistoryProvider(directory,offline).fetch("XAUUSD",Timeframe.M1,start,start))
        assertEquals(2,requests)
        // Corrupt SQLite caches must be discarded rather than treated as valid history.
        File(directory,"XAUUSD-2025.sqlite").writeText("damaged")
        assertNull(HistDataChartHistoryProvider(directory,offline).cached("XAUUSD",Timeframe.M1,start,start))
        assertEquals(bars,HistDataChartHistoryProvider(directory,client).fetch("XAUUSD",Timeframe.M1,start,start))
        assertEquals(4,requests)
    }

    @Test fun publisherDuplicatesAreCountedOnceAndFixedEstDoesNotFollowDst() = runBlocking {
        val provider=HistDataChartHistoryProvider(temp.newFolder())
        provider.importZip("XAUUSD",2025,null,file(zip(listOf(row("20250106 000100"),row("20250701 000000"),row(),row("20250106 000100")).joinToString("\n"))))
        val bars=provider.cached("XAUUSD",Timeframe.M1,start,start+60_000)!!
        assertEquals(listOf(start,start+60_000),bars.map { it.openTime })
        assertEquals(0.0,bars.first().volume,0.0)
        val summer=Instant.parse("2025-07-01T05:00:00Z").toEpochMilli()
        assertEquals(summer,provider.cached("XAUUSD",Timeframe.M1,summer,summer)!!.single().openTime)
    }

    @Test fun conflictingDuplicatesInvalidPricesAndWrongDatesDoNotReplaceGoodCache() = runBlocking {
        val provider=HistDataChartHistoryProvider(temp.newFolder())
        provider.importZip("XAUUSD",2025,null,file(zip(row())))
        for(bad in listOf(row()+"\n"+row(close="2002"),row(close="NaN"),row(close="3000"),row("20240106 000000"))) {
            try { provider.importZip("XAUUSD",2025,null,file(zip(bad)));fail("Malformed source must not commit") }
            catch(_: IllegalArgumentException) { }
            assertEquals(2001.0,provider.cached("XAUUSD",Timeframe.M1,start,start)!!.single().close,0.0)
        }
    }

    @Test fun barsAggregateAcrossAnnualFileBoundariesWithoutPartialCandles() = runBlocking {
        val provider=HistDataChartHistoryProvider(temp.newFolder())
        provider.importZip("XAUUSD",2024,null,file(zip(row("20241231 230000"),2024)))
        provider.importZip("XAUUSD",2025,null,file(zip(row("20250101 000000")+"\n"+row("20250101 025900",close="2005"))))
        val at=Instant.parse("2025-01-01T04:00:00Z").toEpochMilli()
        val bar=provider.cached("XAUUSD",Timeframe.H4,at,at)!!.single()
        assertEquals(at,bar.openTime)
        assertEquals(2005.0,bar.close,0.0)
        assertEquals(at+4*3_600_000L,bar.closeTime)
        assertEquals(HistDataChartHistoryProvider.SOURCE,bar.source)
    }

    @Test fun ambiguousMinutesAndEveryAffectedHigherCandleAreQuarantinedWithoutChoosingPrices() = runBlocking {
        val provider=HistDataChartHistoryProvider(temp.newFolder())
        val rows=(listOf(row(),row(close="2002"))+(1..5).map { row("20250106 000${it}00") }).joinToString("\n")
        provider.importZip("XAUUSD",2025,null,file(zip(rows)))
        val minutes=provider.cached("XAUUSD",Timeframe.M1,start,start+5*60_000)!!
        assertEquals(5,minutes.size)
        assertTrue(minutes.none { it.openTime==start })
        val three=provider.cached("XAUUSD",Timeframe.M3,start,start+180_000)!!
        assertEquals(start+180_000,three.single().openTime)
        assertTrue(provider.cached("XAUUSD",Timeframe.H1,start,start)!!.isEmpty())
        assertNotNull(provider.warning("XAUUSD"))
    }

    @Test fun weeklyBarsStartMondayAndClosedWindowsAreVerifiedEmpty() = runBlocking {
        val provider=HistDataChartHistoryProvider(temp.newFolder())
        provider.importZip("XAUUSD",2025,null,file(zip(row("20250105 190000")+"\n"+row("20250108 190000"))))
        val monday=Instant.parse("2025-01-06T00:00:00Z").toEpochMilli()
        assertEquals(monday,provider.cached("XAUUSD",Timeframe.W1,monday,monday)!!.single().openTime)
        val empty=provider.cached("XAUUSD",Timeframe.M1,start,start)!!
        assertTrue(empty.isEmpty())
    }

    @Test fun onlyTheMatchingFreeDownloadFormCanBeSubmitted() {
        val provider=HistDataChartHistoryProvider(temp.newFolder())
        assertEquals("2025",provider.downloadForm(form(),"XAUUSD",2025,null)["date"])
        for(html in listOf(form(action="https://www.paypal.com/"),form().replace("XAUUSD","EURUSD"),form().replace("M1","T"))) {
            assertThrows(IllegalArgumentException::class.java) { provider.downloadForm(html,"XAUUSD",2025,null) }
        }
    }
}
