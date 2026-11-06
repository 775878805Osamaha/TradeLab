package com.example.core.market

import java.time.Instant
import java.time.ZoneOffset

/** Small absolute-date requests avoid retaining a year of minute bars in memory. */
object ReplayDateWindow {
    data class Window(val from: Long, val to: Long)

    /**
     * Recent FX sessions may be closed for an entire weekend. Search a bounded
     * number of REAL earlier windows without filling those gaps with candles.
     * Each request remains at most [bars] timeframe slots wide.
     */
    fun recentWindows(
        now: Long, interval: Long, bars: Int, endOffsetBars: Int,
        closedSessionLookbackHours: Int = 0,
        brokerTimed: Boolean = false
    ): List<Window> {
        require(interval in 60_000L..604_800_000L && bars in 50..5_000)
        require(endOffsetBars in 0..100_000 && closedSessionLookbackHours in 0..96)
        val latest = HistoricalCandleBoundary.latestClosedRequestTo(now, interval, brokerTimed) -
            interval * endOffsetBars.toLong()
        require(latest >= interval * (bars - 1L)) { "Replay range predates available timestamps" }
        val width = interval * bars.toLong()
        val scanSlots = (closedSessionLookbackHours.toLong() * 3_600_000L + width - 1L) / width
        return (0L..scanSlots.coerceAtMost(48L)).mapNotNull { index ->
            val end = latest - index * width
            if (end < interval * (bars - 1L)) null
            else Window(end - interval * (bars - 1L), end)
        }
    }

    fun oneYearBefore(now: Long): Long = Instant.ofEpochMilli(now)
        .atZone(ZoneOffset.UTC).minusYears(1).toInstant().toEpochMilli()

    fun windows(target: Long, now: Long, interval: Long, bars: Int, brokerTimed: Boolean = false): List<Window> {
        require(interval in 60_000L..604_800_000L && bars in 50..5_000)
        val latest = HistoricalCandleBoundary.latestClosedRequestTo(now, interval, brokerTimed)
        require(target >= 0L && target <= latest) { "Choose a completed historical date" }
        val aligned = if (brokerTimed) target - Math.floorMod(target, 60_000L)
            else HistoricalCandleBoundary.currentOpen(target, interval)
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
