package com.example.core.market

import com.example.core.model.Candle

/**
 * Non-destructive diagnostics for historical chart, replay and backtest data.
 * Market closures are reported as gaps, never filled with invented prices.
 */
object HistoricalDataAudit {
    data class Report(
        val total: Int,
        val valid: Int,
        val invalid: Int,
        val duplicates: Int,
        val outOfOrder: Int,
        val missingIntervals: Long,
        val largestGapIntervals: Long,
        val mixedInstruments: Int,
        val futureBars: Int,
        val safeForBacktest: Boolean,
        val issues: List<String>
    )

    fun inspect(candles: List<Candle>, nowMillis: Long = System.currentTimeMillis()): Report {
        if (candles.isEmpty()) return Report(0, 0, 0, 0, 0, 0, 0, 0, 0,
            false, listOf("No historical candles"))
        val first = candles.first()
        val symbol = first.symbol
        val timeframe = first.timeframe
        val period = timeframe.minutes.toLong() * 60_000L
        val validPeriod = period > 0L
        val seen = HashSet<Triple<String, Int, Long>>()
        var valid = 0
        var invalid = 0
        var duplicates = 0
        var outOfOrder = 0
        var missing = 0L
        var largestGap = 0L
        var mixed = 0
        var future = 0
        var previousOpen: Long? = null
        val issues = mutableListOf<String>()
        candles.forEachIndexed { index, bar ->
            val result = DataIntegrityValidator.validateCandle(bar)
            if (result.isValid) valid++ else {
                invalid++
                if (issues.size < 10) issues += "Invalid bar $index: ${(result as ValidationResult.Invalid).reason}"
            }
            if (bar.symbol != symbol || bar.timeframe != timeframe) mixed++
            if (!seen.add(Triple(bar.symbol, bar.timeframe.minutes, bar.openTime))) duplicates++
            if (bar.closeTime > nowMillis || bar.openTime > nowMillis) future++
            val prev = previousOpen
            if (prev != null) {
                if (bar.openTime <= prev) outOfOrder++
                else if (validPeriod) {
                    val distance = if (bar.openTime > 0L && prev < 0L && bar.openTime > Long.MAX_VALUE + prev) Long.MAX_VALUE else bar.openTime - prev
                    if (distance > period) {
                        val gap = (distance - 1L) / period
                        missing = if (Long.MAX_VALUE - missing < gap) Long.MAX_VALUE else missing + gap
                        largestGap = maxOf(largestGap, gap)
                    }
                }
            }
            previousOpen = bar.openTime
        }
        if (duplicates > 0) issues += "$duplicates duplicate bars"
        if (outOfOrder > 0) issues += "$outOfOrder unordered bars"
        if (mixed > 0) issues += "$mixed mixed-symbol/timeframe bars"
        if (future > 0) issues += "$future unfinished/future bars"
        if (missing > 0) issues += "$missing absent intervals (including market closures)"
        val strict = DataIntegrityValidator.validateHistoricalSeries(candles).isValid
        val safe = validPeriod && strict && future == 0 && duplicates == 0 && outOfOrder == 0 &&
            mixed == 0 && invalid == 0
        if (!strict && issues.size < 15) issues += "Strict historical validation failed"
        return Report(candles.size, valid, invalid, duplicates, outOfOrder,
            missing, largestGap, mixed, future, safe, issues)
    }
}
