package com.example.core.market

import com.example.core.model.Timeframe

/** Public files can lag by days. Request the recent tail before consulting archives. */
object ChartHistorySourceWindow {
    private const val DAY=86_400_000L
    const val RECENT_DAYS=7L
    data class Window(val from: Long, val to: Long)
    data class Split(val archive: Window?, val recent: Window?)
    fun split(timeframe: Timeframe, from: Long, to: Long, now: Long): Split {
        require(from >= 0 && to >= from && now >= 0)
        val today = now / DAY * DAY
        val publicationBoundary=(today-RECENT_DAYS*DAY).coerceAtLeast(0L)
        if (timeframe.minutes >= 1440 || to < publicationBoundary) return Split(Window(from,to),null)
        val recentFrom = maxOf(from,publicationBoundary)
        val interval = timeframe.minutes*60_000L
        return Split(if(from<recentFrom) Window(from,recentFrom-interval) else null,Window(recentFrom,to))
    }
}
