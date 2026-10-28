package com.example.core.market

import com.example.core.model.Timeframe

/** Completed archives cannot cover today's intraday candles. Never skip that tail. */
object ChartHistorySourceWindow {
    data class Window(val from: Long, val to: Long)
    data class Split(val archive: Window?, val recent: Window?)
    fun split(timeframe: Timeframe, from: Long, to: Long, now: Long): Split {
        require(from >= 0 && to >= from && now >= 0)
        val today = now / 86_400_000L * 86_400_000L
        if (timeframe.minutes >= 1440 || to < today) return Split(Window(from,to),null)
        val recentFrom = maxOf(from,today)
        val interval = timeframe.minutes*60_000L
        return Split(if(from<recentFrom) Window(from,recentFrom-interval) else null,Window(recentFrom,to))
    }
}
