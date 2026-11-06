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
    const val AUTO_MAX_HOURS = 72
    const val AUTO_TARGET_BARS = 96
    const val HOUR_MILLIS = 3_600_000L

    data class Window(val end: Long, val hours: Int) {
        val start: Long get() = (end - hours * HOUR_MILLIS).coerceAtLeast(1L)
    }

    fun older(end: Long, hours: Int, maxHours: Int = MAX_WINDOW_HOURS): Window {
        require(end > 0L && maxHours in 1..MAX_WINDOW_HOURS && hours in 1..maxHours)
        if (hours < maxHours) {
            val next = if (hours < STEP_HOURS) minOf(STEP_HOURS, maxHours)
                else (hours + STEP_HOURS).coerceAtMost(maxHours)
            return Window(end, next)
        }
        val earliestEnd = maxHours * HOUR_MILLIS + 1L
        val step = minOf(STEP_HOURS, maxHours)
        val nextEnd = (end - step * HOUR_MILLIS).coerceAtLeast(earliestEnd)
        return Window(nextEnd.coerceAtMost(end), maxHours)
    }

    fun smallerDenseWindow(hours: Int): Int {
        require(hours in 1..MAX_WINDOW_HOURS)
        return (hours / 2).coerceAtLeast(1)
    }

    /** Explicit historical jump keeps the request within the available one-week limit. */
    fun jumpBack(end: Long, hours: Int, days: Int): Window {
        require(end > 0L && hours in 1..MAX_WINDOW_HOURS && days > 0)
        val earliestEnd = hours * HOUR_MILLIS + 1L
        val jumped = (end - days.toLong() * 24L * HOUR_MILLIS)
            .coerceAtLeast(earliestEnd).coerceAtMost(end)
        return Window(jumped, hours)
    }

    fun shouldPrefetchMoreBars(candleCount: Int, hours: Int, manuallyChosen: Boolean,
                               inReplay: Boolean): Boolean =
        !manuallyChosen && !inReplay && candleCount in 0 until AUTO_TARGET_BARS &&
            hours in 1 until AUTO_MAX_HOURS
}
