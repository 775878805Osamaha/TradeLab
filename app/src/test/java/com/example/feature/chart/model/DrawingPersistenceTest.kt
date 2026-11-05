package com.example.feature.chart.model

import androidx.compose.ui.graphics.Color
import org.junit.Assert.*
import org.junit.Test

class DrawingPersistenceTest {
    @Test fun annotationRoundTripsArabicQuotesAndLineBreaks() {
        val drawing = ChartDrawing(tool = DrawingTool.ANNOTATION, symbol = "XAUUSD", timeframe = "M15",
            startPrice = 4000.0, startTime = 123000L, color = Color(0xFF00B7AA),
            text = "دعم \"قوي\"\nشراء \\ اختبار")
        val restored = ChartDrawing.fromEntity(drawing.toEntity())
        assertNotNull(restored)
        assertEquals(drawing.text, restored!!.text)
        assertEquals(drawing.color, restored.color)
        assertEquals(drawing.tool, restored.tool)
    }
    @Test fun existingDrawingWithoutTextRemainsReadable() {
        val drawing = ChartDrawing(tool = DrawingTool.RECTANGLE, symbol = "XAUUSD", timeframe = "M15",
            startPrice = 4000.0, startTime = 123000L, endPrice = 4010.0, endTime = 456000L)
        val oldEntity = drawing.toEntity().copy(pointsJson = "{\"startPrice\":4000.0,\"startTime\":123000,\"endPrice\":4010.0,\"endTime\":456000}")
        val restored = ChartDrawing.fromEntity(oldEntity)
        assertNotNull(restored)
        assertEquals(4010.0, restored!!.endPrice!!, 0.0001)
        assertEquals("تعليق", restored.text)
        assertEquals(DrawingLineStyle.SOLID, restored.lineStyle)
    }

    @Test fun quickEditLineStyleAndThicknessSurviveDatabaseRoundTrip() {
        val drawing = ChartDrawing(id=13, tool=DrawingTool.HORIZONTAL_LINE, symbol="XAUUSD", timeframe="M15",
            startPrice=3912.32,startTime=1_730_000_000_000L,
            color=Color(0xFF4CAF50),secondaryColor=Color(0xFF8B2CF5),strokeWidth=4f,lineStyle=DrawingLineStyle.DOTTED)
        val saved = ChartDrawing.fromEntity(drawing.toEntity())
        assertNotNull(saved)
        assertEquals(DrawingLineStyle.DOTTED,saved!!.lineStyle)
        assertEquals(4f,saved.strokeWidth,0f)
        assertEquals(drawing.color,saved.color)
        assertEquals(drawing.secondaryColor,saved.secondaryColor)
    }

    @Test fun fibonacciLevelsVisibilityAndAppearanceSurviveDatabaseRoundTrip() {
        val config = FibonacciSettings(
            levels = listOf(
                FibonacciLevel(-2.5, Color(0xFFF53149), true),
                FibonacciLevel(0.382, Color(0xFF4CAF50), false),
                FibonacciLevel(1.618, Color(0xFF008577), true)
            ),
            background = true, backgroundOpacity = .45f, extension = FibExtension.RIGHT,
            showPrices = false, reverse = true, logarithmic = true,
            trendLineColor = Color(0xFF808080), trendLineStyle = DrawingLineStyle.DASHED,
            levelLineStyle = DrawingLineStyle.DOTTED, levelLineWidth = 3f,
            labelPosition = FibLabelPosition.RIGHT,
            labelVerticalPosition = FibVerticalPosition.BOTTOM,
            textAlignment = FibTextAlignment.RIGHT,
            textVerticalPosition = FibVerticalPosition.TOP,
            timeRules = FibTimeUnit.entries.map { unit ->
                FibTimeRule(unit, enabled = unit != FibTimeUnit.MINUTES, from = 1, to = unit.upperBound)
            }
        )
        val drawing = ChartDrawing(id = 22, tool = DrawingTool.FIBONACCI,
            symbol = "XAUUSD", timeframe = "M5", startPrice = 4204.64,
            startTime = 1730000000000L, endPrice = 4169.28,
            endTime = 1730000300000L, fibonacci = config)
        val restored = ChartDrawing.fromEntity(drawing.toEntity())
        assertNotNull(restored)
        assertEquals(config, restored!!.fibonacci)
        assertFalse(restored.fibonacci.isVisibleAt("M5"))
        assertEquals(4204.64, restored.startPrice, .001)
        assertEquals(DrawingLineStyle.DOTTED, restored.fibonacci.levelLineStyle)
        assertEquals(3f, restored.fibonacci.levelLineWidth!!, 0f)
    }

    @Test fun fibonacciVersionOnePayloadKeepsItsPreviousSharedDrawingLineAppearance() {
        val current = FibonacciSettings().encode().split('|')
        val oldVersion = (listOf("1") + current.subList(1, 16)).joinToString("|")
        val decoded = FibonacciSettings.decode(oldVersion)
        assertEquals(FibonacciSettings.defaultLevels(), decoded.levels)
        assertNull(decoded.trendLineColor)
        assertNull(decoded.trendLineStyle)
        assertNull(decoded.levelLineStyle)
        assertNull(decoded.levelLineWidth)
    }

    @Test fun fibonacciVersionTwoPayloadRestoresIndependentLinesAndHistoricalLabelPlacement() {
        val modern = FibonacciSettings(labelPosition = FibLabelPosition.RIGHT,
            trendLineStyle = DrawingLineStyle.DOTTED,
            levelLineWidth = 4f).encode().split('|')
        val oldVersion = (listOf("2") + modern.subList(1, 20)).joinToString("|")
        val decoded = FibonacciSettings.decode(oldVersion)
        assertEquals(DrawingLineStyle.DOTTED, decoded.trendLineStyle)
        assertEquals(4f, decoded.levelLineWidth!!, 0f)
        assertEquals(FibLabelPosition.RIGHT, decoded.labelPosition)
        assertEquals(FibVerticalPosition.TOP, decoded.labelVerticalPosition)
        assertEquals(FibTextAlignment.RIGHT, decoded.textAlignment)
        assertEquals(FibVerticalPosition.CENTER, decoded.textVerticalPosition)
    }

    @Test fun oldFibonacciDrawingsKeepTheirPreviousLevels() {
        val drawing = ChartDrawing(tool = DrawingTool.FIBONACCI, symbol = "EURUSD", timeframe = "H1",
            startPrice = 1.08, startTime = 123000L, endPrice = 1.06, endTime = 456000L)
        val old = drawing.toEntity().copy(pointsJson = "{\"startPrice\":1.08,\"startTime\":123000,\"endPrice\":1.06,\"endTime\":456000}")
        val restored = ChartDrawing.fromEntity(old)
        assertNotNull(restored)
        assertEquals(FibonacciCalculator.DEFAULT_LEVELS,
            restored!!.fibonacci.levels.map { it.value })
        assertEquals(FibExtension.BOTH, restored.fibonacci.extension)
        assertEquals(DrawingLineStyle.DASHED, restored.fibonacci.levelLineStyle)
    }
}
