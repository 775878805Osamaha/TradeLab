package com.example.core.market

import android.database.sqlite.SQLiteDatabase
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.*
import java.io.*
import java.time.*
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.zip.ZipFile
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Public website downloads only. No API key, FTP, subscription, or paid endpoint. */
class HistDataChartHistoryProvider(
    private val directory: File,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .followRedirects(false).followSslRedirects(false)
        .cookieJar(AnonymousCookies())
        .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
        .callTimeout(60, java.util.concurrent.TimeUnit.SECONDS).build(),
    private val clock: () -> Long = System::currentTimeMillis
) {
    companion object {
        const val SOURCE = "HISTDATA_BID_HISTORY"
        private val EST = ZoneOffset.ofHours(-5) // Publisher specifies fixed EST, without DST.
        private val FORMAT = DateTimeFormatter.ofPattern("uuuuMMdd HHmmss").withResolverStyle(ResolverStyle.STRICT)
    }
    private class AnonymousCookies: CookieJar {
        private var saved=emptyList<Cookie>()
        @Synchronized override fun saveFromResponse(url: HttpUrl,cookies: List<Cookie>) {
            if(url.host!="www.histdata.com") return
            val names=cookies.map { it.name }.toSet()
            saved=(saved.filter { it.name !in names }+cookies).filter { it.expiresAt>System.currentTimeMillis() }.takeLast(16)
        }
        @Synchronized override fun loadForRequest(url: HttpUrl): List<Cookie> =
            if(url.host!="www.histdata.com") emptyList() else saved.filter { it.matches(url) && it.expiresAt>System.currentTimeMillis() }
    }
    private val lock = Mutex()
    private val warnings=java.util.concurrent.ConcurrentHashMap<String,String>()
    private data class PublicationGap(val requestedUntil: Long,val publishedUntil: Long)
    private val publicationGaps=java.util.concurrent.ConcurrentHashMap<String,PublicationGap>()
    fun warning(symbol: String): String? = listOfNotNull(warnings[symbol],publicationGaps[symbol]?.let {
        "تأخر الأرشيف؛ آخر شموع منشورة حتى ${Instant.ofEpochMilli(it.publishedUntil)}. توجد فجوة في التاريخ الحديث."
    }).takeIf { it.isNotEmpty() }?.joinToString(" ")
    private data class Period(val year: Int, val month: Int?) {
        val key get() = "$year" + (month?.let { "%02d".format(java.util.Locale.US,it) } ?: "")
        val start get() = LocalDate.of(year,month ?: 1,1).atStartOfDay().toInstant(EST).toEpochMilli()
        val end get() = LocalDate.of(year,month ?: 1,1).let { if(month==null) it.plusYears(1) else it.plusMonths(1) }
            .atStartOfDay().toInstant(EST).toEpochMilli()
    }
    private data class Part(val period: Period, val file: File, val until: Long, val conflicts: Int)

    /** null means cache miss; an empty verified cached window is still a valid result. */
    suspend fun cached(symbol: String, tf: Timeframe, from: Long, to: Long): List<Candle>? = withContext(Dispatchers.IO) {
        require(DukascopyChartHistoryProvider.supports(symbol) && from>=0 && to>=from)
        val interval=tf.minutes*60_000L
        require((to-from)/interval<1000 && HistoricalCandleBoundary.isClosedRange(to,clock(),interval))
        lock.withLock {
            val until=to+tf.minutes*60_000L
            val periods=periods(from,until)
            if(periods.first().start>from) return@withLock null
            val parts=periods.map { cachedPart(symbol,it) ?: return@withLock null }
            if(parts.last().until<until) return@withLock null
            read(symbol,tf,from,until,parts)
        }
    }

    suspend fun fetch(symbol: String, tf: Timeframe, from: Long, to: Long): List<Candle> = withContext(Dispatchers.IO) {
        require(DukascopyChartHistoryProvider.supports(symbol) && from>=0 && to>=from)
        val interval=tf.minutes*60_000L
        require((to-from)/interval<1000 && HistoricalCandleBoundary.isClosedRange(to,clock(),interval))
        withTimeoutOrNull(180_000L) {
            lock.withLock {
                check(directory.isDirectory || directory.mkdirs()) { "Historical cache unavailable" }
                val periods=periods(from,to+interval)
                val parts=periods.map { cachedPart(symbol,it) ?: download(symbol,it) }
                if(parts.last().until<to+interval) {
                    publicationGaps[symbol]=PublicationGap(to+interval,parts.last().until)
                    throw ChartHistoryPublicationGapException(parts.last().until)
                }
                val result=read(symbol,tf,from,to+interval,parts)
                trim(parts.map { it.file }.toSet())
                result
            }
        } ?: throw MarketDataRequestException("انتهت مهلة تنزيل الأرشيف المجاني HistData")
    }

    // At most two adjacent source files per request. Returning the newest covered
    // portion advances paging backwards without jumping over an older unloaded part.
    private fun periods(from: Long, until: Long): List<Period> {
        var at=until-1
        val result=mutableListOf<Period>()
        val currentYear=Instant.ofEpochMilli(clock()).atOffset(EST).year
        repeat(2) {
            val date=Instant.ofEpochMilli(at).atOffset(EST)
            val p=Period(date.year,if(date.year<currentYear) null else date.monthValue)
            result.add(p)
            if(p.start<=from) return result.reversed()
            at=p.start-1
        }
        return result.reversed()
    }
    private fun path(symbol: String,p: Period)=File(directory,"$symbol-${p.key}.sqlite")
    private fun cachedPart(symbol: String,p: Period): Part? {
        val file=path(symbol,p)
        if(!file.isFile) return null
        return try {
            SQLiteDatabase.openDatabase(file.path,null,SQLiteDatabase.OPEN_READONLY).use { db ->
                db.rawQuery("SELECT symbol,period,fetched,conflicts FROM meta",null).use { row ->
                    if(!row.moveToFirst() || row.getString(0)!=symbol || row.getString(1)!=p.key) return null
                    val fetched=row.getLong(2)
                    if(fetched<0 || fetched>clock()+60_000L) return null
                    // A file fetched mid-period stays provisional even after the
                    // calendar advances. Never promote that cached prefix to complete.
                    if(fetched<p.end && clock()-fetched>3_600_000L) return null
                    file.setLastModified(clock())
                    if(row.getInt(3)<0) return null
                    val until=if(fetched>=p.end) p.end else {
                        fun latest(table: String)=db.rawQuery("SELECT MAX(t) FROM $table",null).use { last ->
                            if(last.moveToFirst() && !last.isNull(0)) last.getLong(0) else 0L
                        }
                        // Download time says nothing about how far the publisher
                        // has filled the current monthly file. Conflicted originals
                        // still establish publication, while remaining excluded.
                        minOf(p.end,fetched/60_000L*60_000L,maxOf(latest("candles"),latest("quarantine"))+60_000L)
                    }
                    Part(p,file,until,row.getInt(3))
                }
            }
        } catch (_: android.database.sqlite.SQLiteException) { file.delete();null }
    }

    private suspend fun download(symbol: String,p: Period): Part {
        val suffix=p.month?.let { "/$it" } ?: ""
        val page="https://www.histdata.com/download-free-forex-historical-data/?/ascii/1-minute-bar-quotes/${symbol.lowercase(java.util.Locale.US)}/${p.year}$suffix"
        val html=String(bytes(Request.Builder().url(page).build(),131_072),Charsets.UTF_8)
        val fields=downloadForm(html,symbol,p.year,p.month)
        val body=FormBody.Builder().apply { fields.forEach { (key,value) -> add(key,value) } }.build()
        val zipBytes=bytes(Request.Builder().url("https://www.histdata.com/get.php").header("Referer",page).post(body).build(),16*1024*1024)
        require(zipBytes.size>=4 && zipBytes[0]==0x50.toByte() && zipBytes[1]==0x4b.toByte()) { "HistData did not return a ZIP archive" }
        val zip=File.createTempFile("histdata-",".zip",directory)
        try {
            zip.writeBytes(zipBytes)
            importZip(symbol,p.year,p.month,zip)
        } finally { zip.delete() }
        return cachedPart(symbol,p) ?: throw IOException("HistData cache was not committed")
    }

    /** Validate the exact free download form; never submit donation/subscription forms. */
    internal fun downloadForm(html: String,symbol: String,year: Int,month: Int?): Map<String,String> {
        val form=Regex("<form\\b[^>]*\\bid=[\"']file_down[\"'][^>]*>(.*?)</form>",setOf(RegexOption.IGNORE_CASE,RegexOption.DOT_MATCHES_ALL))
            .find(html)?.value ?: throw IOException("HistData free download form unavailable")
        fun attributes(tag: String)=Regex("([a-zA-Z_]+)\\s*=\\s*[\"']([^\"']*)[\"']").findAll(tag)
            .associate { it.groupValues[1].lowercase(java.util.Locale.US) to it.groupValues[2] }
        val attrs=attributes(form.substringBefore('>'))
        require(attrs["action"]=="/get.php" && attrs["method"].equals("POST",true)) { "Unexpected HistData download action" }
        val values=Regex("<input\\b[^>]*>",RegexOption.IGNORE_CASE).findAll(form).map { attributes(it.value) }
            .filter { it["type"].equals("hidden",true) }.associate { it["name"].orEmpty() to it["value"].orEmpty() }
        val period="$year"+(month?.let { "%02d".format(java.util.Locale.US,it) } ?: "")
        require(values.keys==setOf("tk","date","datemonth","platform","timeframe","fxpair") &&
            values["date"]=="$year" && values["datemonth"]==period && values["platform"]=="ASCII" &&
            values["timeframe"]=="M1" && values["fxpair"]==symbol &&
            values["tk"].orEmpty().matches(Regex("[a-fA-F0-9]{16,128}"))) { "HistData download metadata mismatch" }
        return values
    }

    /** Stream a bounded yearly/monthly ZIP into an atomic private SQLite cache. */
    internal suspend fun importZip(symbol: String,year: Int,month: Int?,zip: File) {
        require(DukascopyChartHistoryProvider.supports(symbol))
        val p=Period(year,month)
        val temporary=File.createTempFile("histdata-",".partial",directory)
        var committed=false
        try {
            SQLiteDatabase.openOrCreateDatabase(temporary,null).use { db ->
                db.disableWriteAheadLogging()
                db.rawQuery("PRAGMA journal_mode=DELETE",null).use { it.moveToFirst() }
                db.execSQL("CREATE TABLE candles(t INTEGER PRIMARY KEY,o REAL NOT NULL,h REAL NOT NULL,l REAL NOT NULL,c REAL NOT NULL,v REAL NOT NULL)")
                db.execSQL("CREATE TABLE quarantine(t INTEGER,o REAL,h REAL,l REAL,c REAL,v REAL,PRIMARY KEY(t,o,h,l,c,v))")
                db.execSQL("CREATE TABLE meta(symbol TEXT,period TEXT,fetched INTEGER,row_count INTEGER,duplicates INTEGER,conflicts INTEGER)")
                db.beginTransaction()
                try {
                    var raw=0;var unique=0;var duplicates=0;var expanded=0L
                    val conflicts=HashSet<Long>()
                    val insert=db.compileStatement("INSERT OR IGNORE INTO candles VALUES(?,?,?,?,?,?)")
                    val quarantine=db.compileStatement("INSERT OR IGNORE INTO quarantine VALUES(?,?,?,?,?,?)")
                    fun retainConflict(time: Long,values: List<Double>) {
                        quarantine.bindLong(1,time)
                        values.forEachIndexed { i,value -> quarantine.bindDouble(i+2,value) }
                        quarantine.executeInsert()
                    }
                    try {
                        insert.use { statement ->
                            ZipFile(zip).use { archive ->
                                val all=archive.entries().asSequence().take(33).toList()
                                require(all.size<=32) { "Too many archive members" }
                                val files=all.filter { !it.isDirectory && it.name.endsWith(".csv",true) }
                                require(files.isNotEmpty()) { "No HistData M1 file" }
                                for(entry in files.sortedBy { it.name }) {
                                    val name=entry.name.substringAfterLast('/')
                                    require(name.matches(Regex("DAT_ASCII_${symbol}_M1_${p.year}(?:[0-9]{2})?\\.csv",RegexOption.IGNORE_CASE))) { "Wrong HistData instrument/format" }
                                    val checksum=java.util.zip.CRC32()
                                    java.util.zip.CheckedInputStream(archive.getInputStream(entry),checksum).bufferedReader(Charsets.UTF_8).use { reader ->
                                        while(true) {
                                            val line=reader.readLine() ?: break
                                            expanded+=line.length+1
                                            require(expanded<=64L*1024*1024 && line.length<=256) { "HistData archive exceeds size limit" }
                                            if(line.isBlank()) continue
                                            require(++raw<=600_000) { "HistData file exceeds row limit" }
                                            if(raw%512==0) currentCoroutineContext().ensureActive()
                                            val f=line.removePrefix("\uFEFF").split(';')
                                            require(f.size==6) { "Invalid HistData M1 row" }
                                            val time=LocalDateTime.parse(f[0],FORMAT).toInstant(EST).toEpochMilli()
                                            require(time in p.start until p.end && time%60_000L==0L && time+60_000L<=clock()) { "Invalid HistData timestamp" }
                                            val values=f.drop(1).map { it.toDouble() }
                                            val(o,h,l,c,v)=values
                                            require(values.all { it.isFinite() } && l>0 && l<=minOf(o,c) && h>=maxOf(o,c) && v>=0) { "Invalid HistData OHLCV" }
                                            if(time in conflicts) { retainConflict(time,values);continue }
                                            statement.bindLong(1,time)
                                            values.forEachIndexed { i,value -> statement.bindDouble(i+2,value) }
                                            if(statement.executeInsert()!=-1L) unique++ else {
                                                val previous=db.rawQuery("SELECT o,h,l,c,v FROM candles WHERE t=?",arrayOf(time.toString())).use { existing ->
                                                    require(existing.moveToFirst()) { "Historical cache conflict lookup failed" }
                                                    List(5) { existing.getDouble(it) }
                                                }
                                                if(values.indices.all { previous[it]==values[it] }) duplicates++ else {
                                                    // Preserve BOTH originals for audit. Neither price is chosen
                                                    // for display, and affected aggregates are excluded below.
                                                    retainConflict(time,previous);retainConflict(time,values)
                                                    db.delete("candles","t=?",arrayOf(time.toString()))
                                                    conflicts.add(time);unique--
                                                }
                                            }
                                        }
                                    }
                                    require(checksum.value==entry.crc) { "HistData archive checksum mismatch" }
                                }
                            }
                        }
                    } finally { quarantine.close() }
                    require(unique>0) { "Empty HistData archive" }
                    db.execSQL("INSERT INTO meta VALUES(?,?,?,?,?,?)",arrayOf(symbol,p.key,clock(),unique,duplicates,conflicts.size))
                    currentCoroutineContext().ensureActive()
                    db.setTransactionSuccessful()
                } finally { db.endTransaction() }
            }
            currentCoroutineContext().ensureActive()
            check(temporary.renameTo(path(symbol,p))) { "Could not commit historical cache" }
            committed=true
        } finally { if(!committed) temporary.delete();File(temporary.path+"-journal").delete() }
    }

    private suspend fun read(symbol: String,tf: Timeframe,from: Long,until: Long,parts: List<Part>): List<Candle> {
        publicationGaps[symbol]?.let { if(parts.last().until>=it.requestedUntil) publicationGaps.remove(symbol,it) }
        val interval=tf.minutes*60_000L
        val start=maxOf(from,parts.first().period.start)
        val end=minOf(until,parts.last().until)
        if(end<=start) return emptyList()
        val result=ArrayList<Candle>()
        val affected=HashSet<Long>()
        val count=parts.sumOf { it.conflicts }
        if(count>0) warnings[symbol]="HistData: استُبعدت $count دقيقة بأسعار متعارضة، مع شموع الفريمات المتأثرة."
        else warnings.remove(symbol)
        for(part in parts.filter { it.conflicts>0 }) {
            SQLiteDatabase.openDatabase(part.file.path,null,SQLiteDatabase.OPEN_READONLY).use { db ->
                db.rawQuery("SELECT DISTINCT t FROM quarantine WHERE t>=? AND t<?",arrayOf(start.toString(),end.toString())).use { cursor ->
                    while(cursor.moveToNext()) affected.add(HistoricalCandleBoundary.currentOpen(cursor.getLong(0),interval))
                }
            }
        }
        var bucket=-1L;var o=0.0;var h=0.0;var l=0.0;var c=0.0;var volume=0.0;var rows=0
        fun emit() {
            if(bucket>=start && bucket+interval<=end && bucket !in affected) result.add(Candle(symbol,tf,bucket,
                open=o,high=h,low=l,close=c,volume=volume,closeTime=bucket+interval,source=SOURCE))
        }
        for(part in parts) {
            SQLiteDatabase.openDatabase(part.file.path,null,SQLiteDatabase.OPEN_READONLY).use { db ->
                db.rawQuery("SELECT t,o,h,l,c,v FROM candles WHERE t>=? AND t<? ORDER BY t",arrayOf(start.toString(),end.toString())).use { cursor ->
                    while(cursor.moveToNext()) {
                        if(++rows%512==0) currentCoroutineContext().ensureActive()
                        val next=HistoricalCandleBoundary.currentOpen(cursor.getLong(0),interval)
                        if(next!=bucket) {
                            if(bucket>=0) emit()
                            bucket=next;o=cursor.getDouble(1);h=cursor.getDouble(2);l=cursor.getDouble(3);volume=0.0
                        } else { h=maxOf(h,cursor.getDouble(2));l=minOf(l,cursor.getDouble(3)) }
                        c=cursor.getDouble(4);volume+=cursor.getDouble(5)
                    }
                }
            }
        }
        if(bucket>=0) emit()
        return HistoricalCandleIntegrity.validate(result,from,until,SOURCE,symbol,tf)
    }

    private fun trim(protected: Set<File>) {
        val files=directory.listFiles { file -> file.name.endsWith(".sqlite") }?.sortedBy { it.lastModified() } ?: return
        var total=files.sumOf { it.length() };var count=files.size
        for(file in files) {
            if(count<=4 && total<=256L*1024*1024) break
            if(file in protected) continue
            val size=file.length()
            if(file.delete()) { total-=size;count-- }
        }
    }

    private suspend fun bytes(request: Request,limit: Int): ByteArray = suspendCancellableCoroutine { continuation ->
        val call=client.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object: Callback {
            override fun onFailure(call: Call,e: IOException) {
                if(continuation.isActive) continuation.resumeWithException(MarketDataRequestException("HistData network failure",e))
            }
            override fun onResponse(call: Call,response: Response) {
                try {
                    val data=response.use {
                        if(!it.isSuccessful) throw MarketDataRequestException("HistData HTTP ${it.code}")
                        val input=it.body?.byteStream() ?: throw IOException("Empty HistData response")
                        val out=ByteArrayOutputStream();val buffer=ByteArray(8192)
                        while(true) { val n=input.read(buffer);if(n<0) break;require(out.size()+n<=limit) { "HistData response too large" };out.write(buffer,0,n) }
                        out.toByteArray()
                    }
                    if(continuation.isActive) continuation.resume(data)
                } catch(error: Exception) { if(continuation.isActive) continuation.resumeWithException(error) }
            }
        })
    }
}
