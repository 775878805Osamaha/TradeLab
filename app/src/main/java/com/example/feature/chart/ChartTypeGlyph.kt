package com.example.feature.chart

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp

/** Small chart-specific outline glyphs; the type picker does not borrow generic navigation icons. */
@Composable
internal fun ChartTypeGlyph(type: String, color: Color) {
    Canvas(Modifier.size(27.dp)) {
        val unit = size.minDimension / 24f
        val stroke = 1.65f * unit
        fun point(x: Float, y: Float) = Offset(x * unit, y * unit)
        fun line(x1: Number, y1: Number, x2: Number, y2: Number, width: Float = 1f) =
            drawLine(color, point(x1.toFloat(), y1.toFloat()), point(x2.toFloat(), y2.toFloat()),
                strokeWidth = stroke * width, cap = StrokeCap.Square)
        fun path(vararg values: Float) {
            for (i in 0 until values.size - 2 step 2) {
                line(values[i], values[i + 1], values[i + 2], values[i + 3])
            }
        }
        fun rect(x: Float, y: Float, w: Float, h: Float, solid: Boolean = false) =
            drawRect(color, point(x, y), Size(w * unit, h * unit),
                style = if (solid) Fill else Stroke(stroke))
        fun dot(x: Float, y: Float, radius: Float = 1.25f) =
            drawCircle(color, radius * unit, point(x, y))
        fun candle(x: Float, top: Float, bottom: Float, bodyTop: Float, bodyBottom: Float, w: Float = 3f, solid: Boolean = false) {
            line(x, top, x, bottom)
            rect(x - w / 2f, bodyTop, w, bodyBottom - bodyTop, solid)
        }
        when (type) {
            "bars" -> {
                line(6, 4, 6, 20); line(3.5, 13, 6, 13); line(6, 8, 8.5, 8)
                line(17, 2, 17, 19); line(14.5, 9, 17, 9); line(17, 14, 19.5, 14)
            }
            "candles" -> { candle(7f, 3f, 21f, 7f, 17f); candle(17f, 4f, 20f, 10f, 15f) }
            "hollow" -> {
                candle(7f, 3f, 22f, 7f, 17f)
                for (y in 9..16 step 3) line(5.7, y, 8.3, y + 1.5)
                candle(17f, 4f, 20f, 10f, 15f)
            }
            "volume_candles" -> { candle(7f, 4f, 20f, 8f, 15f, 2f); candle(17f, 2f, 21f, 6f, 18f, 7f) }
            "line" -> path(3f, 17f, 9f, 11f, 14f, 15f, 22f, 6f)
            "line_markers" -> {
                path(2f, 18f, 9f, 9f, 15f, 14f, 22f, 5f)
                dot(9f, 9f, 1.75f); dot(15f, 14f, 1.75f)
            }
            "step" -> path(2f, 20f, 9f, 20f, 9f, 13f, 16f, 13f, 16f, 5f, 22f, 5f)
            "area" -> {
                path(3f, 15f, 8f, 10f, 13f, 14f, 21f, 5f)
                for (x in 4..18 step 3) line(x, 21, x + 3, 18)
            }
            "hlc_area" -> {
                path(2f, 13f, 8f, 6f, 13f, 12f, 22f, 3f)
                path(2f, 19f, 8f, 12f, 13f, 18f, 22f, 9f)
                for (x in 3..19 step 4) line(x, 21, x + 3, 18)
            }
            "baseline" -> {
                path(2f, 13f, 8f, 8f, 14f, 12f, 22f, 4f)
                for (x in 2..20 step 4) line(x, 18, x + 1, 18)
            }
            "columns" -> { rect(4f, 14f, 4f, 7f); rect(10f, 7f, 4f, 14f); rect(16f, 16f, 4f, 5f) }
            "high_low" -> { rect(6f, 5f, 4f, 15f); rect(15f, 8f, 4f, 10f) }
            "footprint" -> {
                candle(6f, 3f, 21f, 7f, 17f, 3f)
                for (y in 6..20 step 4) line(13, y, 21, y)
            }
            "time_price" -> {
                for (x in 3..17 step 5) line(x, 4, x, 21)
                for (y in 5..20 step 5) line(3, y, 20, y)
                rect(4f, 11f, 5f, 4f, true); rect(14f, 16f, 5f, 4f, true)
            }
            "session_volume" -> {
                line(4, 3, 4, 22)
                rect(4f, 5f, 7f, 3f); rect(4f, 10f, 15f, 3f)
                rect(4f, 15f, 11f, 3f); rect(4f, 20f, 6f, 2f)
            }
            "heikin" -> { candle(7f, 4f, 22f, 10f, 18f); candle(17f, 2f, 20f, 6f, 16f) }
            "renko" -> { rect(3f, 15f, 5f, 6f); rect(9f, 10f, 5f, 6f); rect(15f, 5f, 5f, 6f) }
            "line_break" -> { rect(4f, 5f, 4f, 14f); rect(10f, 3f, 4f, 18f); rect(16f, 9f, 4f, 10f) }
            "kagi" -> {
                path(4f, 20f, 4f, 9f, 10f, 9f, 10f, 4f)
                line(10, 4, 16, 4, 1.8f); line(16, 4, 16, 16, 1.8f)
                path(16f, 16f, 21f, 16f, 21f, 7f)
            }
            "point_figure" -> {
                for (y in listOf(5f, 12f, 19f)) {
                    line(3, y - 2, 7, y + 2); line(7, y - 2, 3, y + 2)
                }
                for (y in listOf(6f, 13f, 20f)) {
                    drawCircle(color, 2.15f * unit, point(13f, y), style = Stroke(stroke))
                }
                line(19, 4, 23, 8); line(23, 4, 19, 8)
            }
            "range" -> {
                line(6, 4, 6, 19); line(3, 14, 6, 14); line(6, 7, 9, 7)
                line(15, 3, 15, 17); line(12, 9, 15, 9); line(15, 14, 18, 14)
                path(13f, 20f, 17f, 20f, 17f, 23f)
            }
        }
    }
}
