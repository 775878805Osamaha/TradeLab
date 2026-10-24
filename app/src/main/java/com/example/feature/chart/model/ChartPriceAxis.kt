package com.example.feature.chart.model

import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow

/**
 * Deterministic, platform-independent price-axis ticks.
 * Labels use 1/2/5 × 10^n intervals; grid levels do not jump to arbitrary decimals.
 */
object ChartPriceAxis {
    data class Tick(val price: Double, val fractionFromTop: Float, val label: String)
    data class Scale(val step: Double, val decimals: Int, val ticks: List<Tick>)

    fun calculate(minPrice: Double, maxPrice: Double, heightPx: Float, targetGapPx: Float = 86f): Scale {
        if (!minPrice.isFinite() || !maxPrice.isFinite() || minPrice >= maxPrice ||
            !heightPx.isFinite() || heightPx <= 0f) return Scale(1.0, 0, emptyList())
        val count = (heightPx / targetGapPx.coerceAtLeast(24f)).toInt().coerceIn(2, 20)
        val raw = (maxPrice - minPrice) / count
        if (!raw.isFinite() || raw <= 0.0) return Scale(1.0, 0, emptyList())
        val power = 10.0.pow(floor(log10(raw)))
        val normalized = raw / power
        val multiplier = when {
            normalized <= 1.0 -> 1.0
            normalized <= 2.0 -> 2.0
            normalized <= 5.0 -> 5.0
            else -> 10.0
        }
        val step = multiplier * power
        val decimals = (-floor(log10(step))).toInt().coerceIn(0, 8)
        val start = ceil(minPrice / step) * step
        val countTicks = floor(((maxPrice - start) / step).coerceAtLeast(0.0) + 1e-8)
            .toInt().coerceIn(0, 40)
        val ticks = (0..countTicks).mapNotNull { i ->
            val value = start + i * step
            if (value < minPrice - step * 1e-8 || value > maxPrice + step * 1e-8) null
            else Tick(value, ((maxPrice - value) / (maxPrice - minPrice)).toFloat(),
                String.format(Locale.US, "%,." + decimals + "f", value))
        }
        return Scale(step, decimals, ticks)
    }
}
