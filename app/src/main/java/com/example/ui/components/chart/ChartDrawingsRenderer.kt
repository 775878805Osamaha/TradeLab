package com.example.ui.components.chart

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import com.example.feature.chart.model.*
import com.example.ui.theme.TradingAccent
import com.example.ui.theme.TradingGold
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.exp
import kotlin.math.ln

object ChartDrawingsRenderer {

    fun drawDrawings(
        scope: DrawScope,
        drawings: List<ChartDrawing>,
        transform: ChartTransform,
        history: List<com.example.core.model.Candle> = transform.visibleCandles,
        vwaps: Map<Long,List<VwapPoint>> = emptyMap(),
        images: Map<Long,androidx.compose.ui.graphics.ImageBitmap?> = emptyMap(),
        profiles: Map<Long,List<CandleVolumeProfile.Bin>> = emptyMap()
    ) {
        for (d in drawings) {
            val startX = transform.timeToX(d.startTime) ?: continue
            val startY = transform.priceToY(d.startPrice)
            val endX = d.endTime?.let { transform.timeToX(it) }
            val endY = d.endPrice?.let { transform.priceToY(it) }
            val lineEffect = when (d.lineStyle) {
                DrawingLineStyle.SOLID -> null
                DrawingLineStyle.DASHED -> PathEffect.dashPathEffect(floatArrayOf(10f, 6f))
                DrawingLineStyle.DOTTED -> PathEffect.dashPathEffect(floatArrayOf(2f, 6f))
            }

            when (d.tool) {
                DrawingTool.HORIZONTAL_LINE -> {
                    scope.drawLine(
                        color = d.color,
                        start = Offset(0f, startY),
                        end = Offset(transform.chartWidth, startY),
                        strokeWidth = d.strokeWidth,
                        pathEffect = lineEffect
                    )
                    // Price tag on right edge
                    scope.drawContext.canvas.nativeCanvas.apply {
                        val paint = android.graphics.Paint().apply {
                            color = d.color.toArgb()
                            textSize = 20f
                            isAntiAlias = true
                        }
                        drawText(QuotePriceFormatter.forSymbol(d.startPrice,transform.visibleCandles.firstOrNull()?.symbol), transform.chartWidth - 65f, startY - 4f, paint)
                        if (d.text != "تعليق" && d.text.isNotBlank())
                            drawText(d.text.take(48), transform.chartWidth / 2f, startY - 8f, paint)
                    }
                }
                DrawingTool.VERTICAL_LINE -> {
                    scope.drawLine(
                        color = d.color,
                        start = Offset(startX, 0f),
                        end = Offset(startX, transform.chartHeight),
                        strokeWidth = d.strokeWidth,
                        pathEffect = lineEffect
                    )
                }
                DrawingTool.TRENDLINE -> {
                    if (endX != null && endY != null) {
                        scope.drawLine(
                            color = d.color,
                            start = Offset(startX, startY),
                            end = Offset(endX, endY),
                            strokeWidth = d.strokeWidth,
                            pathEffect = lineEffect
                        )
                        if (d.text != "تعليق" && d.text.isNotBlank()) {
                            scope.drawContext.canvas.nativeCanvas.drawText(d.text.take(48), endX, endY - 10f,
                                android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = d.color.toArgb(); textSize = 20f })
                        }
                    }
                }
                DrawingTool.ANNOTATION -> {
                    scope.drawContext.canvas.nativeCanvas.drawText(d.text, startX, startY,
                        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                            color = d.color.toArgb()
                            textSize = with(scope) { 12f * density }
                        })
                }
                DrawingTool.ELLIPSE -> {
                    if (endX != null && endY != null) {
                        scope.drawOval(d.color, Offset(min(startX, endX), min(startY, endY)),
                            Size(abs(endX - startX), abs(endY - startY)), style = Stroke(d.strokeWidth))
                    }
                }
                DrawingTool.RECTANGLE -> {
                    if (endX != null && endY != null) {
                        val left = min(startX, endX)
                        val top = min(startY, endY)
                        val rectWidth = abs(endX - startX)
                        val rectHeight = abs(endY - startY)

                        scope.drawRect(
                            color = d.color.copy(alpha = 0.18f),
                            topLeft = Offset(left, top),
                            size = Size(rectWidth, rectHeight)
                        )
                        scope.drawRect(
                            color = d.color,
                            topLeft = Offset(left, top),
                            size = Size(rectWidth, rectHeight),
                            style = Stroke(width = d.strokeWidth)
                        )
                    }
                }
                DrawingTool.FIBONACCI -> {
                    val fib = d.fibonacci
                    if (d.endPrice != null && fib.isVisibleAt(d.timeframe)) {
                        val firstX = min(startX, endX ?: startX)
                        val lastX = max(startX, endX ?: startX)
                        val x1 = if (fib.extension == FibExtension.LEFT || fib.extension == FibExtension.BOTH) 0f else firstX
                        val x2 = if (fib.extension == FibExtension.RIGHT || fib.extension == FibExtension.BOTH) transform.chartWidth else lastX
                        if (fib.trendLine && endX != null && endY != null) {
                            scope.drawLine(d.color, Offset(startX, startY), Offset(endX, endY),
                                strokeWidth = d.strokeWidth, pathEffect = lineEffect)
                        }
                        val active = fib.levels.filter { it.enabled && it.value.isFinite() }
                            .map { level ->
                                val ratio = if (fib.reverse) 1.0 - level.value else level.value
                                val price = if (fib.logarithmic && d.startPrice > 0 && d.endPrice > 0)
                                    exp(ln(d.startPrice) + (ln(d.endPrice) - ln(d.startPrice)) * ratio)
                                else d.startPrice + (d.endPrice - d.startPrice) * ratio
                                Triple(level, price, transform.priceToY(price))
                            }.filter { it.third.isFinite() }
                        if (fib.background) {
                            active.sortedBy { it.third }.zipWithNext().forEach { (top, bottom) ->
                                scope.drawRect(
                                    color = (if (fib.singleColor) d.color else top.first.color)
                                        .copy(alpha = fib.backgroundOpacity.coerceIn(0f, 1f)),
                                    topLeft = Offset(x1, top.third),
                                    size = Size((x2 - x1).coerceAtLeast(0f), (bottom.third - top.third).coerceAtLeast(0f))
                                )
                            }
                        }
                        for ((level, price, y) in active) {
                            val levelColor = if (fib.singleColor) d.color else level.color
                            scope.drawLine(levelColor, Offset(x1, y), Offset(x2, y),
                                strokeWidth = d.strokeWidth, pathEffect = lineEffect)
                            if (fib.showText && (fib.showLevels || fib.showPrices)) {
                                val levelLabel = if (fib.labelsAsPercents)
                                    String.format(Locale.US, "%.1f%%", level.value * 100.0)
                                else level.value.toString().removeSuffix(".0")
                                val label = listOfNotNull(
                                    levelLabel.takeIf { fib.showLevels },
                                    QuotePriceFormatter.forSymbol(price,transform.visibleCandles.firstOrNull()?.symbol)
                                        .takeIf { fib.showPrices }
                                ).joinToString(" (") + if (fib.showLevels && fib.showPrices) ")" else ""
                                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                                    color = levelColor.toArgb()
                                    textSize = with(scope) { fib.textSize * density }
                                }
                                val x = when (fib.labelPosition) {
                                    FibLabelPosition.LEFT -> x1 + 5f
                                    FibLabelPosition.RIGHT -> x2 - paint.measureText(label) - 5f
                                    FibLabelPosition.CENTER -> (x1 + x2 - paint.measureText(label)) / 2f
                                }
                                scope.drawContext.canvas.nativeCanvas.drawText(label, x, y - 4f, paint)
                            }
                        }
                    }
                }
                DrawingTool.MEASUREMENT -> {
                    if (d.endTime != null && d.endPrice != null && endX != null && endY != null) {
                        val result = MeasurementCalculator.calculate(d.startPrice, d.endPrice, d.startTime, d.endTime)
                        // Arrow line
                        scope.drawLine(
                            color = d.color,
                            start = Offset(startX, startY),
                            end = Offset(endX, endY),
                            strokeWidth = d.strokeWidth
                        )
                        // Measurement Box
                        val midX = (startX + endX) / 2f
                        val midY = (startY + endY) / 2f
                        scope.drawContext.canvas.nativeCanvas.apply {
                            val paint = android.graphics.Paint().apply {
                                color = android.graphics.Color.WHITE
                                textSize = 22f
                                isAntiAlias = true
                            }
                            val text = String.format(
                                Locale.US,
                                "%s%.2f (%s%.2f%%) • %s",
                                if (result.priceDiff >= 0) "+" else "",
                                result.priceDiff,
                                if (result.percentDiff >= 0) "+" else "",
                                result.percentDiff,
                                result.durationFormatted
                            )
                            drawText(text, midX - 80f, midY - 8f, paint)
                        }
                    }
                }
                DrawingTool.NONE -> {}
                else -> ExtendedDrawingRenderer.draw(scope, d, transform, history, vwaps, images, profiles)
            }
        }
    }
}
