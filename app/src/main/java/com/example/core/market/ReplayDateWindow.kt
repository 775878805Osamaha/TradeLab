package com.example.core.market

import java.time.Instant
import java.time.ZoneOffset

/** Small absolute-date requests avoid retaining a year of minute bars in memory. */
object ReplayDateWindow {
    data class Window(val from: Long, val to: Long)

    fun oneYearBefore(now: Long): Long = Instant.ofEpochMilli(now)
        .atZone(ZoneOffset.UTC).minusYears(1).toInstant().toEpochMilli()

    fun windows(target: Long, now: Long, interval: Long, bars: Int): List<Window> {
        require(interval in 60_000L..604_800_000L && bars in 50..5_000)
        val latest = HistoricalCandleBoundary.currentOpen(now, interval) - interval
        require(target >= 0L && target <= latest) { "Choose a completed historical date" }
        val aligned = HistoricalCandleBoundary.currentOpen(target, interval).coerceAtLeast(0L)
        val first = (aligned - 20L * interval).coerceAtLeast(0L)
        // Search contiguous windows over closed sessions, never retry transport errors.
        val searchUntil = minOf(latest, aligned + 7L * 86_400_000L)
        val result = ArrayList<Window>()
        var from = first
        while (from <= searchUntil && result.size < 64) {
            val to = minOf(latest, from + (bars - 1L) * interval)
            result.add(Window(from, to))
            from = to + interval
        }
        return result
    }
}
