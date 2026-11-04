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
}
