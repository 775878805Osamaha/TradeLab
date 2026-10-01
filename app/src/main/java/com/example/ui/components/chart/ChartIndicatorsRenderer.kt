package com.example.ui.components.chart

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import com.example.core.indicators.BollingerBandsResult
import com.example.core.indicators.MacdResult
import com.example.feature.chart.model.ChartTransform
import com.example.feature.chart.model.IndicatorSettings
import com.example.ui.theme.*
import java.util.Locale

object ChartIndicatorsRenderer {

    fun drawMainOverlays(
        scope: DrawScope,
        transform: ChartTransform,
        settings: IndicatorSettings,
        smaValues: List<Double?>,
        emaValues: List<Double?>,
        bollingerValues: List<BollingerBandsResult?>,
        vwapValues: List<Double>
    ) {
        val total = transform.visibleCandles.size
        if (total <= 1) return

        // 1. Bollinger Bands
        if (settings.isBollingerEnabled && bollingerValues.size >= total) {
            val upperPath = Path()
            val lowerPath = Path()
            val fillPath = Path()
            var first = true

            for (i in 0 until total) {
                val bb = bollingerValues.getOrNull(i) ?: continue
                val x = transform.candleIndexToX(i)
                val yUp = transform.priceToY(bb.upper)
                val yLow = transform.priceToY(bb.lower)

                if (first) {
                    upperPath.moveTo(x, yUp)
                    lowerPath.moveTo(x, yLow)
                    fillPath.moveTo(x, yUp)
                    first = false
                } else {
                    upperPath.lineTo(x, yUp)
                    lowerPath.lineTo(x, yLow)
                    fillPath.lineTo(x, yUp)
                }
            }

            // Complete fill path in reverse for lower band
            for (i in total - 1 downTo 0) {
                val bb = bollingerValues.getOrNull(i) ?: continue
                val x = transform.candleIndexToX(i)
                val yLow = transform.priceToY(bb.lower)
                fillPath.lineTo(x, yLow)
            }
            fillPath.close()

            scope.drawPath(path = fillPath, color = Color(0x188B5CF6))
            scope.drawPath(path = upperPath, color = Color(0xFF8B5CF6), style = Stroke(width = 1.5f))
            scope.drawPath(path = lowerPath, color = Color(0xFF8B5CF6), style = Stroke(width = 1.5f))
        }

        // 2. SMA
        if (settings.isSmaEnabled && smaValues.size >= total) {
            val path = Path()
            var started = false
            for (i in 0 until total) {
                val v = smaValues.getOrNull(i) ?: continue
                val x = transform.candleIndexToX(i)
                val y = transform.priceToY(v)
                if (!started) {
                    path.moveTo(x, y)
                    started = true
                } else {
                    path.lineTo(x, y)
                }
            }
            if (started) {
                scope.drawPath(path = path, color = TradingGold, style = Stroke(width = 2.0f))
            }
        }

        // 3. EMA
        if (settings.isEmaEnabled && emaValues.size >= total) {
            val path = Path()
            var started = false
            for (i in 0 until total) {
                val v = emaValues.getOrNull(i) ?: continue
                val x = transform.candleIndexToX(i)
                val y = transform.priceToY(v)
                if (!started) {
                    path.moveTo(x, y)
                    started = true
                } else {
                    path.lineTo(x, y)
                }
            }
            if (started) {
                scope.drawPath(path = path, color = TradingCyan, style = Stroke(width = 2.0f))
            }
        }

        // 4. VWAP
        if (settings.isVwapEnabled && vwapValues.size >= total) {
            val path = Path()
            var started = false
            for (i in 0 until total) {
                val v = vwapValues.getOrNull(i) ?: continue
                val x = transform.candleIndexToX(i)
                val y = transform.priceToY(v)
                if (!started) {
                    path.moveTo(x, y)
                    started = true
                } else {
                    path.lineTo(x, y)
                }
            }
            if (started) {
                scope.drawPath(path = path, color = Color(0xFFEC4899), style = Stroke(width = 2.0f))
            }
        }
    }

    fun drawSubpanel(
        scope: DrawScope,
        panelTop: Float,
        panelHeight: Float,
        chartWidth: Float,
        transform: ChartTransform,
        settings: IndicatorSettings,
        rsiValues: List<Double?>,
        macdValues: List<MacdResult?>,
        atrValues: List<Double?>
    ) {
        val total = transform.visibleCandles.size
        if (total <= 1) return

        // Panel background & divider
        scope.drawLine(
            color = TradingBorder,
            start = Offset(0f, panelTop),
            end = Offset(chartWidth, panelTop),
            strokeWidth = 1.5f
        )

        if (settings.isRsiEnabled && rsiValues.size >= total) {
            // RSI PANEL: Range 0..100
            val y70 = panelTop + (0.3f * panelHeight)
            val y30 = panelTop + (0.7f * panelHeight)

            // Overbought / Oversold guides
            scope.drawLine(color = TradingNegative.copy(alpha = 0.5f), start = Offset(0f, y70), end = Offset(chartWidth, y70), strokeWidth = 1f)
            scope.drawLine(color = TradingPositive.copy(alpha = 0.5f), start = Offset(0f, y30), end = Offset(chartWidth, y30), strokeWidth = 1f)

            val rsiPath = Path()
            var started = false
            for (i in 0 until total) {
                val rsi = rsiValues.getOrNull(i) ?: continue
                val x = transform.candleIndexToX(i)
                val normalizedY = (1.0 - (rsi / 100.0).coerceIn(0.0, 1.0)).toFloat()
                val y = panelTop + (normalizedY * panelHeight)
                if (!started) {
                    rsiPath.moveTo(x, y)
                    started = true
                } else {
                    rsiPath.lineTo(x, y)
                }
            }
            if (started) {
                scope.drawPath(path = rsiPath, color = Color(0xFFA855F7), style = Stroke(width = 2.0f))
            }

            scope.drawContext.canvas.nativeCanvas.apply {
                val p = android.graphics.Paint().apply { color = android.graphics.Color.parseColor("#A855F7"); textSize = 20f; isAntiAlias = true }
                val latest = rsiValues.lastOrNull { it != null } ?: 50.0
                drawText(String.format(Locale.US, "RSI(%d): %.1f", settings.rsiPeriod, latest), 12f, panelTop + 22f, p)
            }
        } else if (settings.isMacdEnabled && macdValues.size >= total) {
            // MACD PANEL
            val macds = macdValues.filterNotNull()
            val maxVal = maxOf(1.0, macds.maxOfOrNull { maxOf(kotlin.math.abs(it.macd), kotlin.math.abs(it.signal), kotlin.math.abs(it.histogram)) } ?: 1.0)
            val zeroY = panelTop + (panelHeight / 2f)

            // Zero line
            scope.drawLine(color = TradingBorder.copy(alpha = 0.4f), start = Offset(0f, zeroY), end = Offset(chartWidth, zeroY), strokeWidth = 1f)

            for (i in 0 until total) {
                val m = macdValues.getOrNull(i) ?: continue
                val x = transform.candleIndexToX(i)
                val histY = zeroY - ((m.histogram / maxVal).coerceIn(-1.0, 1.0) * (panelHeight * 0.45f)).toFloat()
                val histColor = if (m.histogram >= 0) TradingPositive else TradingNegative

                scope.drawLine(
                    color = histColor.copy(alpha = 0.7f),
                    start = Offset(x, zeroY),
                    end = Offset(x, histY),
                    strokeWidth = transform.candleWidthPx * 0.6f
                )
            }

            scope.drawContext.canvas.nativeCanvas.apply {
                val p = android.graphics.Paint().apply { color = android.graphics.Color.CYAN; textSize = 20f; isAntiAlias = true }
                drawText("MACD (12, 26, 9)", 12f, panelTop + 22f, p)
            }
        } else if (settings.isAtrEnabled && atrValues.size >= total) {
            // ATR PANEL
            val atrs = atrValues.filterNotNull()
            val maxAtr = maxOf(0.001, atrs.maxOrNull() ?: 1.0)
            val minAtr = maxOf(0.0, atrs.minOrNull() ?: 0.0)
            val span = (maxAtr - minAtr).coerceAtLeast(0.0001)

            val atrPath = Path()
            var started = false
            for (i in 0 until total) {
                val a = atrValues.getOrNull(i) ?: continue
                val x = transform.candleIndexToX(i)
                val norm = ((a - minAtr) / span).coerceIn(0.0, 1.0).toFloat()
                val y = panelTop + panelHeight - (norm * (panelHeight * 0.8f)) - (panelHeight * 0.1f)
                if (!started) {
                    atrPath.moveTo(x, y)
                    started = true
                } else {
                    atrPath.lineTo(x, y)
                }
            }
            if (started) {
                scope.drawPath(path = atrPath, color = TradingGold, style = Stroke(width = 2.0f))
            }

            scope.drawContext.canvas.nativeCanvas.apply {
                val p = android.graphics.Paint().apply { color = android.graphics.Color.YELLOW; textSize = 20f; isAntiAlias = true }
                val latest = atrValues.lastOrNull { it != null } ?: 0.0
                drawText(String.format(Locale.US, "ATR(%d): %.4f", settings.atrPeriod, latest), 12f, panelTop + 22f, p)
            }
        }
    }
}
