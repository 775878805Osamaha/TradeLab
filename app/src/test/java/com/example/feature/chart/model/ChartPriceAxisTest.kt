package com.example.feature.chart.model

import org.junit.Assert.*
import org.junit.Test

class ChartPriceAxisTest {
    @Test fun roundedGoldPrices() {
        val result = ChartPriceAxis.calculate(4000.0, 4050.0, 500f)
        assertTrue(result.ticks.isNotEmpty())
        assertTrue(result.ticks.all { it.price in 4000.0..4050.0 })
        assertTrue(result.ticks.zipWithNext().all { (a, b) -> b.price > a.price })
    }

    @Test fun forexPrecisionIsRetained() {
        val result = ChartPriceAxis.calculate(1.0820, 1.0890, 500f)
        assertTrue(result.decimals >= 3)
        assertTrue(result.ticks.any { it.label.contains(".") })
    }

    @Test fun zeroAndNegativeRangesAreRejected() {
        assertTrue(ChartPriceAxis.calculate(3.0, 3.0, 400f).ticks.isEmpty())
        assertTrue(ChartPriceAxis.calculate(5.0, 3.0, 400f).ticks.isEmpty())
    }

    @Test fun nonFiniteInputsAreRejected() {
        assertTrue(ChartPriceAxis.calculate(Double.NaN, 2.0, 400f).ticks.isEmpty())
        assertTrue(ChartPriceAxis.calculate(1.0, Double.POSITIVE_INFINITY, 400f).ticks.isEmpty())
        assertTrue(ChartPriceAxis.calculate(1.0, 2.0, Float.NaN).ticks.isEmpty())
    }

    @Test fun labelsDoNotExceedAxisBounds() {
        for (range in listOf(1.0000 to 1.0008, 2000.0 to 2100.0, 90000.0 to 95000.0)) {
            val scale = ChartPriceAxis.calculate(range.first, range.second, 800f)
            assertTrue(scale.ticks.all { it.fractionFromTop in 0f..1f })
            assertTrue(scale.ticks.size <= 41)
        }
    }

    @Test fun tallerChartAllowsAtLeastAsManyTicks() {
        val small = ChartPriceAxis.calculate(4000.0, 4100.0, 240f)
        val tall = ChartPriceAxis.calculate(4000.0, 4100.0, 1000f)
        assertTrue(tall.ticks.size >= small.ticks.size)
    }

    @Test fun ticksAreMultiplesOfStep() {
        val scale = ChartPriceAxis.calculate(4011.3, 4067.8, 600f)
        assertTrue(scale.ticks.all { tick ->
            val ratio = tick.price / scale.step
            kotlin.math.abs(ratio - kotlin.math.round(ratio)) < 1e-6
        })
    }

    @Test fun emptyHeightProducesNoTicks() {
        assertTrue(ChartPriceAxis.calculate(1.0, 2.0, 0f).ticks.isEmpty())
    }
}
