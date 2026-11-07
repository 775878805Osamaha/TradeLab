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
    // Initial chart should usually contain enough candles for a full screen
    // and several backwards gestures, without loading a full broker week.
    const val AUTO_MAX_HOURS = 96
    const val AUTO_TARGET_BARS = 160
    const val HOUR_MILLIS = 3_600_000L

    /** Small price ranges produce many bars from fewer quotes. Avoid downloading
     * six hours of gold ticks just to paint the first screen of 100-range bars. */
    fun initialWindowHours(sizeInPriceTicks: Int): Int {
        require(sizeInPriceTicks in 1..100_000)
        return when {
            sizeInPriceTicks <= 100 -> 1
            sizeInPriceTicks <= 250 -> 2
            sizeInPriceTicks <= 500 -> 3
            else -> 6
        }
    }

    data class Window(val end: Long, val hours: Int) {
        val start: Long get() = (end - hours * HOUR_MILLIS).coerceAtLeast(1L)
    }

    fun older(end: Long, hours: Int, maxHours: Int = MAX_WINDOW_HOURS): Window {
        require(end > 0L && maxHours in 1..MAX_WINDOW_HOURS && hours in 1..maxHours)
        if (hours < maxHours) {
            // Large Range intervals can produce very few candles even after
            // several hours. Increase window size progressively so a user
            // doesn't need 27 separate requests before reaching one week.
            // The broker's seven-day maximum and density fallback still apply.
            val increment = when {
                hours < STEP_HOURS -> STEP_HOURS - hours
                hours < 24 -> 6
                hours < 48 -> 12
                hours < 96 -> 24
                else -> 36
            }
            val next = (hours + increment).coerceAtMost(maxHours)
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
