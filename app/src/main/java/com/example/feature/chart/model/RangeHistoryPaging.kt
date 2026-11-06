package com.example.feature.chart.model

/**
 * Progressively extends a true-tick Range chart without asking cTrader for
 * more than one week in a single visible window. After a week is loaded, the
 * window moves backwards in small steps; there is no hard-coded earliest
 * market date. The broker's available historical quotes are the limit.
 */
object RangeHistoryPaging {
    const val STEP_HOURS = 6
    const val MAX_WINDOW_HOURS = 7 * 24
    const val AUTO_MAX_HOURS = 48
    const val AUTO_TARGET_BARS = 48
    const val HOUR_MILLIS = 3_600_000L

    data class Window(val end: Long, val hours: Int) {
        val start: Long get() = (end - hours * HOUR_MILLIS).coerceAtLeast(1L)
    }

    fun older(end: Long, hours: Int): Window {
        require(end > 0L && hours in 1..MAX_WINDOW_HOURS)
        if (hours < MAX_WINDOW_HOURS) {
            val next = if (hours < STEP_HOURS) STEP_HOURS
                else (hours + STEP_HOURS).coerceAtMost(MAX_WINDOW_HOURS)
            return Window(end, next)
        }
        val earliestEnd = MAX_WINDOW_HOURS * HOUR_MILLIS + 1L
        val nextEnd = (end - STEP_HOURS * HOUR_MILLIS).coerceAtLeast(earliestEnd)
        return Window(nextEnd.coerceAtMost(end), MAX_WINDOW_HOURS)
    }

    fun shouldPrefetchMoreBars(candleCount: Int, hours: Int, manuallyChosen: Boolean,
                               inReplay: Boolean): Boolean =
        !manuallyChosen && !inReplay && candleCount in 0 until AUTO_TARGET_BARS &&
            hours in 1 until AUTO_MAX_HOURS
}
