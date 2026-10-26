package com.example.feature.chart

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/** Native, scalable line icons following the supplied reference geometry. */
internal object ReferenceChartIcons {
    private fun icon(name: String, block: PathBuilder.() -> Unit) = ImageVector.Builder(
        name, 24.dp, 24.dp, 24f, 24f
    ).apply {
        path(fill = null, stroke = SolidColor(Color.White), strokeLineWidth = 1.4f,
            strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round, pathBuilder = block)
    }.build()
    private fun PathBuilder.ring(x: Float, y: Float, r: Float) {
        moveTo(x + r, y)
        arcTo(r, r, 0f, true, true, x - r, y)
        arcTo(r, r, 0f, true, true, x + r, y)
    }
    val Crosshair = icon("ReferenceCrosshair") {
        ring(12f, 12f, 3f)
        moveTo(12f, 2f); lineTo(12f, 9f); moveTo(12f, 15f); lineTo(12f, 22f)
        moveTo(2f, 12f); lineTo(9f, 12f); moveTo(15f, 12f); lineTo(22f, 12f)
    }
    val Trend = icon("ReferenceTrend") {
        moveTo(5f, 19f); lineTo(11f, 12f); lineTo(20f, 4f)
        ring(5f, 19f, 1.5f); ring(11f, 12f, 1.5f); ring(20f, 4f, 1.5f)
    }
    val Horizontal = icon("ReferenceHorizontal") {
        moveTo(2f, 12f); lineTo(10f, 12f); moveTo(14f, 12f); lineTo(22f, 12f)
        ring(12f, 12f, 2f)
    }
    val Fibonacci = icon("ReferenceFibonacci") {
        moveTo(3f, 5f); lineTo(21f, 5f); moveTo(3f, 10f); lineTo(17f, 10f)
        moveTo(3f, 15f); lineTo(14f, 15f); moveTo(3f, 20f); lineTo(10f, 20f)
        moveTo(5f, 21f); lineTo(20f, 3f)
    }
    val Shapes = icon("ReferenceShapes") {
        moveTo(5f, 17f); lineTo(12f, 7f); lineTo(20f, 4f)
        moveTo(6f, 17f); lineTo(19f, 20f); lineTo(13f, 8f)
        ring(4f, 18f, 2f); ring(12f, 7f, 2f); ring(21f, 4f, 2f); ring(20f, 21f, 2f)
    }
    val Pencil = icon("ReferencePencil") {
        moveTo(4f, 16f); lineTo(17f, 3f); curveTo(19f, 1f, 23f, 5f, 21f, 7f)
        lineTo(8f, 20f); lineTo(3f, 21f); close()
        moveTo(5f, 16f); lineTo(8f, 19f); moveTo(16f, 4f); lineTo(20f, 8f)
    }
    val Rectangle = icon("ReferenceRectangle") {
        moveTo(4f, 4f); lineTo(20f, 4f); lineTo(20f, 20f); lineTo(4f, 20f); close()
        ring(4f, 4f, 1.5f); ring(20f, 4f, 1.5f); ring(4f, 20f, 1.5f); ring(20f, 20f, 1.5f)
    }
    val Circle = icon("ReferenceCircle") { ring(12f, 12f, 9f) }
    val Magnet = icon("ReferenceMagnet") {
        moveTo(5f, 21f); lineTo(5f, 9f); curveTo(5f, -1f, 19f, -1f, 19f, 9f)
        lineTo(19f, 21f); lineTo(15f, 21f); lineTo(15f, 9f)
        curveTo(15f, 4f, 9f, 4f, 9f, 9f); lineTo(9f, 21f); close()
        moveTo(5f, 17f); lineTo(9f, 17f); moveTo(15f, 17f); lineTo(19f, 17f)
    }
}
