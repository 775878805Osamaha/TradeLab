package com.example.feature.chart.model

import androidx.compose.ui.geometry.Offset
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class DrawingSnapTest {
    private val bars = listOf(Candle("XAUUSD", Timeframe.M15, 0, 899999,
        100.0, 110.0, 90.0, 105.0, 10.0))
    private val transform = ChartTransform(bars, 80.0, 120.0, 300f, 400f, 20f)

    @Test fun disabledMagnetPreservesExactCoordinates() {
        val point = Offset(297f, 131f)
        assertEquals(point, transform.snapDrawingPoint(point, false))
    }
    @Test fun magnetSnapsToNearestRevealedOhlc() {
        val point = Offset(294f, transform.priceToY(104.0))
        val snapped = transform.snapDrawingPoint(point, true)
        assertEquals(transform.candleIndexToX(0), snapped.x, 0.001f)
        assertEquals(105.0, transform.yToPrice(snapped.y), 0.00001)
    }
    @Test fun magnetWorksAfterPricePanAndZoom() {
        val moved = transform.copy(minPrice = 95.0, maxPrice = 115.0, candleWidthPx = 40f)
        val point = Offset(285f, moved.priceToY(109.0))
        val snapped = moved.snapDrawingPoint(point, true)
        assertEquals(110.0, moved.yToPrice(snapped.y), 0.00001)
    }
    @Test fun emptyReplayDoesNotInventSnapPoint() {
        val point = Offset(50f, 50f)
        assertEquals(point, transform.copy(visibleCandles = emptyList()).snapDrawingPoint(point, true))
    }
}
