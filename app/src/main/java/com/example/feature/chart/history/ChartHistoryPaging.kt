package com.example.feature.chart.history

import com.example.core.market.HistoricalCandleIntegrity
import com.example.core.market.MarketDataRequestException
import com.example.core.market.NoHistoricalCandlesException
import com.example.core.market.ChartHistoryPublicationGapException
import com.example.core.market.HistoricalCandleBoundary
import com.example.core.market.VerifiedMarketQuote
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.io.IOException

/** Timestamp paging has no cumulative candle/offset ceiling. Each request stays bounded. */
object ChartHistoryPaging {
    const val PAGE_BARS = 500
    private const val DAY_MILLIS = 86_400_000L
    // FX metals and currencies can have multi-day broker closures. Searching
    // just four calendar days can wrongly report end-of-history after a long
    // holiday even when the next older real candle exists. Keep the search
    // bounded and require a confirmed empty provider window at every step.
    private const val BROKER_CLOSED_SESSION_SCAN_DAYS = 14L
    private const val EXCHANGE_CLOSED_SESSION_SCAN_DAYS = 4L

    suspend fun before(
        symbol: String,
        timeframe: Timeframe,
        oldestOpen: Long,
        pageBars: Int = PAGE_BARS,
        fetch: suspend (Long, Long) -> List<Candle>
    ): List<Candle> {
        require(pageBars in 1..PAGE_BARS) { "Invalid chart history page size" }
        return loadBefore(symbol,timeframe,oldestOpen,0,pageBars,fetch)
    }

    private suspend fun loadBefore(
        symbol: String, timeframe: Timeframe, oldestOpen: Long, coverageRedirects: Int, pageBars: Int,
        fetch: suspend (Long,Long) -> List<Candle>
    ): List<Candle> {
        val interval = timeframe.minutes * 60_000L
        if (oldestOpen < interval) return emptyList()
        val brokerTimed = symbol in VerifiedMarketQuote.forexSymbols
        // Scan only confirmed-empty contiguous windows; do not fabricate bars
        // or confuse a provider error with a closed market session.
        val windowSpan = interval * pageBars
        val scanDays = if (brokerTimed) BROKER_CLOSED_SESSION_SCAN_DAYS
            else EXCHANGE_CLOSED_SESSION_SCAN_DAYS
        val windows = ((scanDays * DAY_MILLIS + windowSpan - 1L) / windowSpan)
            .coerceAtLeast(1L)
        for (window in 0L until windows) {
            currentCoroutineContext().ensureActive()
            // A broker's immediately previous bar may have opened less than
            // one nominal interval before the oldest (DST/session changes).
            // Stop one minute before the oldest real open, not one whole bar.
            val end = oldestOpen - (if (brokerTimed) 60_000L else interval) - window * windowSpan
            if (end < 0L) break
            var failure: IOException? = null
            var confirmedEmpty = false
            for (bars in listOf(pageBars, 100, 40, 1).distinct().filter { it <= pageBars }) {
                // Source-specific windows cover all minutes without skipping
                // shifted broker opens. Binance remains UTC-grid aligned.
                val start = end - (bars - 1L) * interval -
                    (if (brokerTimed) interval - 60_000L else 0L)
                if (start < 0L) continue
                val raw = try {
                    fetch(start, end)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (gap: ChartHistoryPublicationGapException) {
                    // Follow only a verified exclusive publication boundary.
                    // Align backwards so no partial higher-timeframe bar is accepted.
                    if(gap.publishedUntil<=0L || coverageRedirects>=2) throw gap
                    val before=HistoricalCandleBoundary.currentOpen(gap.publishedUntil,interval)
                    if(before<=0L || before>=oldestOpen) throw gap
                    return loadBefore(symbol,timeframe,before,coverageRedirects+1,pageBars,fetch)
                } catch (_: NoHistoricalCandlesException) {
                    emptyList()
                } catch (error: IOException) {
                    // An outage/rate limit is never an empty trading session.
                    if (generateSequence<Throwable>(error) { it.cause }
                            .any { it is MarketDataRequestException }) throw error
                    failure = error
                    continue
                }
                if (raw.isEmpty()) {
                    // Only a verified EMPTY full window allows advancing across it.
                    if (bars == pageBars) confirmedEmpty = true
                    if (confirmedEmpty) break
                    continue
                }
                // Validation failures propagate; they must not hide missing bars.
                // The next bar's timestamp is already known from the visible
                // chart. At a shortened broker session, clamp the older bar's
                // nominal close to that REAL next open before merging history.
                val bounded = if (brokerTimed) raw.map { candle ->
                    if (candle.source.startsWith("ctrader:", ignoreCase = true) &&
                        candle.closeTime > oldestOpen && candle.openTime < oldestOpen) {
                        candle.copy(closeTime = oldestOpen)
                    } else candle
                } else raw
                return HistoricalCandleIntegrity.validate(bounded, start, end + interval,
                    expectedSymbol = symbol, expectedTimeframe = timeframe)
            }
            if (!confirmedEmpty) throw (failure ?: IOException("تعذر التحقق من الشموع الأقدم"))
        }
        return emptyList()
    }

    /** Merge two verified chronological series in O(n + page), preserving every older bar. */
    fun merge(existing: List<Candle>, incoming: List<Candle>): List<Candle> {
        if (incoming.isEmpty()) return existing
        val page = incoming.sortedBy { it.openTime }
        if (existing.isEmpty()) return page
        // The usual deep-history page sits strictly before the existing
        // candles. Bulk copies avoid comparing 100k timestamps every 500-bar
        // download, and maintain the exact same chronological viewport anchor.
        if (page.last().openTime < existing.first().openTime) {
            return ArrayList<Candle>(existing.size + page.size).apply {
                addAll(page)
                addAll(existing)
            }
        }
        // Live streams and closed-bar refreshes normally touch only the tail.
        // Keep incoming candles authoritative on an overlapping last open.
        if (page.first().openTime > existing.last().openTime) {
            return ArrayList<Candle>(existing.size + page.size).apply {
                addAll(existing)
                addAll(page)
            }
        }
        if (page.first().openTime == existing.last().openTime &&
            page.zipWithNext().all { (a, b) -> a.openTime < b.openTime }) {
            return ArrayList<Candle>(existing.size + page.size - 1).apply {
                addAll(existing.subList(0, existing.lastIndex))
                addAll(page)
            }
        }
        val merged = ArrayList<Candle>(existing.size + page.size)
        var i = 0
        var j = 0
        while (i < existing.size && j < page.size) {
            when {
                existing[i].openTime < page[j].openTime -> merged.add(existing[i++])
                existing[i].openTime > page[j].openTime -> merged.add(page[j++])
                else -> { merged.add(page[j++]); i++ }
            }
        }
        while (i < existing.size) merged.add(existing[i++])
        while (j < page.size) merged.add(page[j++])
        return merged
    }
}
