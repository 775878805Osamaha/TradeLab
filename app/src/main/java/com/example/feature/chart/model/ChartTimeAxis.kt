package com.example.feature.chart.model

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * UTC chart time-axis labels. Use compact intraday times and a full
 * date/time label when crossing a UTC day boundary.
 */
object ChartTimeAxis {
    private val utc = TimeZone.getTimeZone("UTC")

    fun dayKey(epochMillis: Long): Long = Math.floorDiv(epochMillis, 86_400_000L)

    fun label(epochMillis: Long, previousDisplayedMillis: Long?): String {
        val format = if (previousDisplayedMillis == null ||
            dayKey(previousDisplayedMillis) != dayKey(epochMillis)) "MM/dd HH:mm" else "HH:mm"
        return SimpleDateFormat(format, Locale.US).apply { timeZone = utc }
            .format(Date(epochMillis))
    }

    fun shouldDisplay(leftPx: Float, rightPx: Float, chartWidthPx: Float,
                      previousRightPx: Float, gapPx: Float = 16f): Boolean =
        leftPx.isFinite() && rightPx.isFinite() && chartWidthPx > 0f &&
            leftPx >= 4f && rightPx <= chartWidthPx - 4f &&
            leftPx >= previousRightPx + gapPx && rightPx >= leftPx
}
