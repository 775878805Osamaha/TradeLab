package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe

/** Exhausted recent retention is not evidence that the older archive is empty. */
object ChartRecentHistory {
    suspend fun load(
        timeframe: Timeframe, from: Long, to: Long, now: Long,
        recent: suspend () -> List<Candle>,
        archive: suspend (Long,Long) -> List<Candle>
    ): List<Candle> {
        val bars=try { recent() } catch (_: NoHistoricalCandlesException) { emptyList() }
        // A returned page advances only to its actual oldest bar. Try archives
        // on the next request when the recent provider is exhausted.
        if(bars.isNotEmpty()) return bars
        val today=now/86_400_000L*86_400_000L
        val completedTo=minOf(to,today-timeframe.minutes*60_000L)
        return if(completedTo>=from) archive(from,completedTo) else emptyList()
    }
}
