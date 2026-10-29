package com.example.feature.chart.history

import com.example.core.market.HistoricalCandleIntegrity
import com.example.core.market.MarketDataRequestException
import com.example.core.market.NoHistoricalCandlesException
import com.example.core.market.ChartHistoryPublicationGapException
import com.example.core.market.HistoricalCandleBoundary
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.io.IOException

/** Timestamp paging has no cumulative candle/offset ceiling. Each request stays bounded. */
object ChartHistoryPaging {
    const val PAGE_BARS = 500

    suspend fun before(
        symbol: String,
        timeframe: Timeframe,
        oldestOpen: Long,
        fetch: suspend (Long, Long) -> List<Candle>
    ): List<Candle> = loadBefore(symbol,timeframe,oldestOpen,0,fetch)

    private suspend fun loadBefore(
        symbol: String, timeframe: Timeframe, oldestOpen: Long, coverageRedirects: Int,
        fetch: suspend (Long,Long) -> List<Candle>
    ): List<Candle> {
        val interval = timeframe.minutes * 60_000L
        if (oldestOpen < interval) return emptyList()
        // Scan contiguous windows spanning at least a long closed FX weekend.
        val windowSpan = interval * PAGE_BARS
        val windows = ((4L * 86_400_000L + windowSpan - 1L) / windowSpan).coerceAtLeast(1L)
        for (window in 0L until windows) {
            currentCoroutineContext().ensureActive()
            val end = oldestOpen - interval - window * windowSpan
            if (end < 0L) break
            var failure: IOException? = null
            var confirmedEmpty = false
            for (bars in listOf(PAGE_BARS, 100, 40, 1)) {
                // Keep weekly requests aligned to Monday even near Unix epoch.
                val start = end - (bars - 1L) * interval
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
                    return loadBefore(symbol,timeframe,before,coverageRedirects+1,fetch)
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
                    if (bars == PAGE_BARS) confirmedEmpty = true
                    if (confirmedEmpty) break
                    continue
                }
                // Validation failures propagate; they must not hide missing bars.
                return HistoricalCandleIntegrity.validate(raw, start, end + interval,
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
