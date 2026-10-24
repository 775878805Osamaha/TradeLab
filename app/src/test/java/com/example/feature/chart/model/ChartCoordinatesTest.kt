package com.example.feature.chart.model

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.abs

class ChartCoordinatesTest {
    @Test fun fingerLeftMovesCandleLeft() {
        val x0 = ChartCoordinates.candleX(49, 50, 600f, 12f, 0f)
        val x1 = ChartCoordinates.candleX(49, 50, 600f, 12f, 150f)
        assertEquals(-150f, x1 - x0, 0.001f)
    }

    @Test fun fingerRightMovesCandleRight() {
        val x0 = ChartCoordinates.candleX(49, 50, 600f, 12f, 0f)
        val x1 = ChartCoordinates.candleX(49, 50, 600f, 12f, -8f)
        assertEquals(8f, x1 - x0, 0.001f)
    }

    @Test fun futureSpaceCentersLastCandle() {
        val viewport = ChartViewport.window(300, 600f, 12f, -294f)
        val count = viewport.endIndex - viewport.startIndex
        val x = ChartCoordinates.candleX(count - 1, count, 600f, 12f, viewport.fractionalScrollPx)
        assertEquals(300f, x, 0.001f)
    }

    @Test fun historyMovesOlderCandlesIntoView() {
        val before = ChartViewport.window(300, 600f, 12f, 0f)
        val after = ChartViewport.window(300, 600f, 12f, 24f)
        assertEquals(before.startIndex - 2, after.startIndex)
    }

    @Test fun indexToXAndBackIsConsistent() {
        for (width in listOf(6f, 12f, 25f, 80f)) {
            for (offset in listOf(-150f, 0f, 2f, 135f)) {
                for (index in 0 until 25) {
                    val x = ChartCoordinates.candleX(index, 25, 600f, width, offset)
                    assertEquals(index, ChartCoordinates.candleIndex(x, 25, 600f, width, offset))
                }
            }
        }
    }

    @Test fun priceCoordinateRoundTrip() {
        for (price in listOf(4000.0, 4010.5, 4032.0, 4050.0)) {
            val y = ChartCoordinates.priceY(price, 4000.0, 4050.0, 700f)
            assertEquals(price, ChartCoordinates.yPrice(y, 4000.0, 4050.0, 700f), 0.0001)
        }
    }

    @Test fun axisExtremesAreStable() {
        assertEquals(0f, ChartCoordinates.priceY(4050.0, 4000.0, 4050.0, 700f), 0f)
        assertEquals(700f, ChartCoordinates.priceY(4000.0, 4000.0, 4050.0, 700f), 0f)
    }

    @Test fun emptySeriesDoesNotCrash() {
        assertEquals(-1, ChartCoordinates.candleIndex(100f, 0, 600f, 12f, 0f))
        assertEquals(0f, ChartCoordinates.candleX(0, 0, 600f, 12f, 0f), 0f)
    }

    @Test fun futureCoordinatesAreNotClippedToArbitraryThousandPixels() {
        val x = ChartCoordinates.candleX(0, 500, 600f, 80f, 0f)
        assertTrue(x < -1000f)
    }
}
