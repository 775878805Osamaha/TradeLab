package com.example.core.market

import com.example.core.model.Candle
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

/**
 * TradingView-style Phantom Bars are a VISUAL projection of untraded price gaps.
 * They are never broker quotes, must never be cached as genuine range history,
 * and must never be used for execution, backtests or trade statistics.
 *
 * The source list stays untouched. Real cTrader RangeBarsEngine bars remain the
 * only source of trading data; projection is performed in the chart UI only.
 */
object RangePhantomBars {
    const val SOURCE_PREFIX = "visual-only:range-phantom:"
    private const val MAX_STEPS_PER_GAP = 256
    private const val MAX_TOTAL_RENDER_BARS = 20_000

    fun isPhantom(candle: Candle): Boolean = candle.source.startsWith(SOURCE_PREFIX)

    fun project(actualBars: List<Candle>, tickSize: Double, rangeTicks: Int): List<Candle> {
        if (actualBars.isEmpty()) return actualBars
        require(tickSize.isFinite() && tickSize > 0.0 && rangeTicks in 1..100_000)
        val projected = ArrayList<Candle>(actualBars.size)
        var previous: Candle? = null

        for (real in actualBars) {
            if (projected.size >= MAX_TOTAL_RENDER_BARS) {
                // Preserve the genuine remaining bars if a pathological
                // price feed would expand the virtual display excessively.
                projected.add(real)
                previous = real
                continue
            }
            // The gap from the previous real close to the next real open has
            // no intervening quote. Virtual candles are visibly marked.
            previous?.let { older ->
                val gap = segments(older.close, real.open, real, rangeTicks, tickSize)
                if (projected.size + gap.size < MAX_TOTAL_RENDER_BARS)
                    projected.addAll(gap)
            }

            // A single actual quote may overshoot several complete ranges.
            // Split only its displayed BODY. Keep the observed extremes as
            // virtual wicks so no broker high/low silently disappears.
            val split = segments(real.open, real.close, real, rangeTicks, tickSize).toMutableList()
            if (split.isEmpty() || projected.size + split.size >= MAX_TOTAL_RENDER_BARS)
                projected.add(real)
            else {
                val highIndex = if (real.close >= real.open) split.lastIndex else 0
                val lowIndex = if (real.close >= real.open) 0 else split.lastIndex
                split[highIndex] = split[highIndex].copy(high = max(split[highIndex].high, real.high))
                split[lowIndex] = split[lowIndex].copy(low = min(split[lowIndex].low, real.low))
                projected.addAll(split)
            }
            previous = real
        }
        return projected
    }

    private fun segments(from: Double, to: Double, template: Candle,
                         rangeTicks: Int, tickSize: Double): List<Candle> {
        val distance = abs(to - from)
        if (!distance.isFinite()) return emptyList()
        val distanceTicks = (distance / tickSize).roundToLong()
        if (distanceTicks < rangeTicks * 1.5) return emptyList()
        // Merge small residual overshoots into the final segment, instead of
        // showing a tiny 0.01-range phantom candle after a full range.
        val completeRanges = distanceTicks / rangeTicks
        val remainder = distanceTicks % rangeTicks
        val extra = if (remainder >= rangeTicks / 4.0) 1 else 0
        val steps = (completeRanges + extra).toInt()
        if (steps < 2 || steps > MAX_STEPS_PER_GAP) return emptyList()

        val direction = if (to > from) 1.0 else -1.0
        val parts = ArrayList<Candle>(steps)
        for (i in 0 until steps) {
            val start = if (i == 0) from else from + direction *
                min(i.toLong() * rangeTicks, distanceTicks) * tickSize
            val finish = if (i == steps - 1) to
                else from + direction *
                    min((i + 1L) * rangeTicks, distanceTicks) * tickSize
            parts.add(template.copy(
                open = start,
                high = max(start, finish),
                low = min(start, finish),
                close = finish,
                volume = 0.0,
                source = SOURCE_PREFIX + template.source
            ))
        }
        return parts
    }
}
