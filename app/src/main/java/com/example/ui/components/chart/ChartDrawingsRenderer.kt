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

            when (d.tool) {
                DrawingTool.HORIZONTAL_LINE -> {
                    scope.drawLine(
                        color = d.color,
                        start = Offset(0f, startY),
                        end = Offset(transform.chartWidth, startY),
                        strokeWidth = d.strokeWidth,
                        pathEffect = d.lineStyle.pathEffect(d.strokeWidth)
                    )
                    // Price tag on right edge
                    scope.drawContext.canvas.nativeCanvas.apply {
                        val paint = android.graphics.Paint().apply {
                            color = d.color.toArgb()
                            textSize = 20f
                            isAntiAlias = true
                        }
                        drawText(QuotePriceFormatter.forSymbol(d.startPrice,transform.visibleCandles.firstOrNull()?.symbol), transform.chartWidth - 65f, startY - 4f, paint)
                    }
                }
                DrawingTool.VERTICAL_LINE -> {
                    scope.drawLine(
                        color = d.color,
                        start = Offset(startX, 0f),
                        end = Offset(startX, transform.chartHeight),
                        strokeWidth = d.strokeWidth,
                        pathEffect = d.lineStyle.pathEffect(d.strokeWidth)
                    )
                }
                DrawingTool.TRENDLINE -> {
                    if (endX != null && endY != null) {
                        scope.drawLine(
                            color = d.color,
                            start = Offset(startX, startY),
                            end = Offset(endX, endY),
                            strokeWidth = d.strokeWidth,
                            pathEffect = d.lineStyle.pathEffect(d.strokeWidth)
                        )
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
                        scope.drawOval(d.color.copy(alpha=d.fillOpacity),Offset(min(startX,endX),min(startY,endY)),Size(abs(endX-startX),abs(endY-startY)))
                        scope.drawOval(d.color, Offset(min(startX, endX), min(startY, endY)),
                            Size(abs(endX - startX), abs(endY - startY)), style = Stroke(d.strokeWidth,pathEffect=d.lineStyle.pathEffect(d.strokeWidth)))
                    }
                }
                DrawingTool.RECTANGLE -> {
                    if (endX != null && endY != null) {
                        val left = min(startX, endX)
                        val top = min(startY, endY)
                        val rectWidth = abs(endX - startX)
                        val rectHeight = abs(endY - startY)

                        scope.drawRect(
                            color = d.color.copy(alpha = d.fillOpacity),
                            topLeft = Offset(left, top),
                            size = Size(rectWidth, rectHeight)
                        )
                        scope.drawRect(
                            color = d.color,
                            topLeft = Offset(left, top),
                            size = Size(rectWidth, rectHeight),
                            style = Stroke(width = d.strokeWidth,pathEffect=d.lineStyle.pathEffect(d.strokeWidth))
                        )
                    }
                }
                DrawingTool.FIBONACCI -> {
                    if (d.endPrice != null) {
                        val levels = FibonacciCalculator.calculateLevels(d.startPrice, d.endPrice)
                        for ((lvl, price) in levels) {
                            val y = transform.priceToY(price)
                            scope.drawLine(
                                color = d.color.copy(alpha = 0.8f),
                                start = Offset(0f, y),
                                end = Offset(transform.chartWidth, y),
                                strokeWidth = d.strokeWidth,
                                pathEffect = d.lineStyle.pathEffect(d.strokeWidth)
                            )
                            scope.drawContext.canvas.nativeCanvas.apply {
                                val paint = android.graphics.Paint().apply {
                                    color = d.color.toArgb()
                                    textSize = 18f
                                    isAntiAlias = true
                                }
                                val lbl = String.format(Locale.US, "%.1f%% (%s)", lvl * 100, QuotePriceFormatter.forSymbol(price,transform.visibleCandles.firstOrNull()?.symbol))
                                drawText(lbl, 10f, y - 4f, paint)
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
                            strokeWidth = d.strokeWidth,
                            pathEffect = d.lineStyle.pathEffect(d.strokeWidth)
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
