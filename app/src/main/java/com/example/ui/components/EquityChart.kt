package com.example.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.model.EquityPoint
import com.example.ui.theme.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

enum class ChartCurveType(val displayNameAr: String) {
    EQUITY_AND_BALANCE("الرصيد وحقوق الملكية"),
    BALANCE_ONLY("منحنى الرصيد (Balance)"),
    DRAWDOWN("منحنى التراجع (Drawdown)")
}

@Composable
fun EquityCurveChart(
    points: List<EquityPoint>,
    initialBalance: Double,
    modifier: Modifier = Modifier,
    isPercentageMode: Boolean = false,
    curveType: ChartCurveType = ChartCurveType.EQUITY_AND_BALANCE
) {
    if (points.isEmpty()) {
        Box(
            modifier = modifier
                .fillMaxWidth()
                .height(180.dp)
                .testTag("equity_chart_empty"),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "لا توجد صفقات منفذة بعد لرسم المنحنى",
                color = TradingTextSecondary,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        return
    }

    var selectedIndex by remember { mutableStateOf<Int?>(null) }
    val sdf = remember { SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.US) }

    val finalEquity = points.lastOrNull()?.equity ?: initialBalance
    val isNetProfit = finalEquity >= initialBalance
    val primaryCurveColor = if (isNetProfit) TradingPositive else TradingNegative

    Column(modifier = modifier) {
        // Interactive tooltip when crosshair is dragged or tapped
        selectedIndex?.let { idx ->
            if (idx in points.indices) {
                val p = points[idx]
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 6.dp),
                    shape = RoundedCornerShape(6.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingElevated)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = sdf.format(Date(p.timestamp)),
                            fontSize = 11.sp,
                            color = TradingTextSecondary
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(
                                text = if (isPercentageMode) {
                                    val pct = ((p.balance - initialBalance) / initialBalance) * 100.0
                                    String.format(Locale.US, "الرصيد: %s%.1f%%", if (pct >= 0) "+" else "", pct)
                                } else {
                                    String.format(Locale.US, "الرصيد: $%.2f", p.balance)
                                },
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = TradingTextPrimary
                            )
                            Text(
                                text = if (isPercentageMode) {
                                    String.format(Locale.US, "التراجع: -%.1f%%", p.drawdownPercentage)
                                } else {
                                    String.format(Locale.US, "التراجع: -$%.2f", p.drawdown)
                                },
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = TradingNegative
                            )
                        }
                    }
                }
            }
        }

        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(210.dp)
                .testTag("equity_curve_canvas")
                .pointerInput(points) {
                    detectDragGestures(
                        onDragStart = { offset ->
                            val rightAxisWidth = 115f
                            val chartWidth = (size.width - rightAxisWidth).coerceAtLeast(1f)
                            val fraction = (offset.x / chartWidth).coerceIn(0f, 1f)
                            val maxIdx = (points.size - 1).coerceAtLeast(0)
                            selectedIndex = if (maxIdx > 0) (fraction * maxIdx).toInt().coerceIn(0, maxIdx) else 0
                        },
                        onDrag = { change, _ ->
                            change.consume()
                            val rightAxisWidth = 115f
                            val chartWidth = (size.width - rightAxisWidth).coerceAtLeast(1f)
                            val fraction = (change.position.x / chartWidth).coerceIn(0f, 1f)
                            val maxIdx = (points.size - 1).coerceAtLeast(0)
                            selectedIndex = if (maxIdx > 0) (fraction * maxIdx).toInt().coerceIn(0, maxIdx) else 0
                        }
                    )
                }
                .pointerInput(points) {
                    detectTapGestures { offset ->
                        val rightAxisWidth = 115f
                        val chartWidth = (size.width - rightAxisWidth).coerceAtLeast(1f)
                        val fraction = (offset.x / chartWidth).coerceIn(0f, 1f)
                        val maxIdx = (points.size - 1).coerceAtLeast(0)
                        selectedIndex = if (maxIdx > 0) (fraction * maxIdx).toInt().coerceIn(0, maxIdx) else 0
                    }
                }
        ) {
            val width = size.width
            val height = size.height
            val rightAxisWidth = 115f
            val chartWidth = (width - rightAxisWidth).coerceAtLeast(1f)
            val chartHeight = (height - 30f).coerceAtLeast(1f)

            fun indexToX(i: Int): Float {
                if (points.size <= 1) return 0f
                val ratio = (i.toFloat() / (points.size - 1)).coerceIn(0f, 1f)
                return ratio * chartWidth
            }

            if (curveType == ChartCurveType.DRAWDOWN) {
                // DRAWDOWN CURVE MODE
                val maxDdVal = max(1.0, points.maxOfOrNull { if (isPercentageMode) it.drawdownPercentage else it.drawdown } ?: 1.0) * 1.1

                fun ddToY(dd: Double): Float {
                    if (dd.isNaN() || dd.isInfinite() || maxDdVal <= 0.0) return 0f
                    val normalized = (dd / maxDdVal).coerceIn(0.0, 1.0)
                    return (normalized * chartHeight).toFloat()
                }

                // Grid lines for Drawdown
                for (step in 0..4) {
                    val y = (step / 4f) * chartHeight
                    val ddVal = (step / 4.0) * maxDdVal
                    drawLine(
                        color = TradingBorder.copy(alpha = 0.35f),
                        start = Offset(0f, y),
                        end = Offset(chartWidth, y),
                        strokeWidth = 1f
                    )
                    drawContext.canvas.nativeCanvas.apply {
                        val paint = android.graphics.Paint().apply {
                            color = android.graphics.Color.parseColor("#9CA3AF")
                            textSize = 22f
                            isAntiAlias = true
                        }
                        val label = if (isPercentageMode) String.format(Locale.US, "-%.1f%%", ddVal) else String.format(Locale.US, "-$%.1f", ddVal)
                        drawText(label, chartWidth + 8f, y + 8f, paint)
                    }
                }

                // Draw Drawdown area & stroke
                val ddPath = Path()
                val ddAreaPath = Path()
                ddAreaPath.moveTo(0f, 0f)

                points.forEachIndexed { i, p ->
                    val x = indexToX(i)
                    val v = if (isPercentageMode) p.drawdownPercentage else p.drawdown
                    val y = ddToY(v)
                    if (i == 0) {
                        ddPath.moveTo(x, y)
                        ddAreaPath.lineTo(x, y)
                    } else {
                        ddPath.lineTo(x, y)
                        ddAreaPath.lineTo(x, y)
                    }
                }
                ddAreaPath.lineTo(chartWidth, 0f)
                ddAreaPath.close()

                drawPath(path = ddAreaPath, color = TradingNegative.copy(alpha = 0.15f))
                drawPath(path = ddPath, color = TradingNegative, style = Stroke(width = 2.5f))

            } else {
                // BALANCE & EQUITY CURVE MODE
                val balances = points.map { it.balance }
                val equities = points.map { it.equity }
                val minVal = min(initialBalance * 0.95, (balances + equities).minOrNull() ?: initialBalance)
                val maxVal = max(initialBalance * 1.05, (balances + equities).maxOrNull() ?: initialBalance)
                val span = (maxVal - minVal).coerceAtLeast(1.0)

                fun valueToY(v: Double): Float {
                    if (v.isNaN() || v.isInfinite() || span <= 0.0) return chartHeight * 0.5f
                    val normalized = ((v - minVal) / span).coerceIn(0.0, 1.0)
                    return (chartHeight - (normalized * chartHeight)).toFloat()
                }

                // Initial baseline
                val initialY = valueToY(initialBalance)
                drawLine(
                    color = TradingBorder,
                    start = Offset(0f, initialY),
                    end = Offset(chartWidth, initialY),
                    strokeWidth = 1.5f
                )

                // Grid lines & labels
                for (step in 0..4) {
                    val y = (step / 4f) * chartHeight
                    val v = minVal + ((4 - step) / 4.0) * span
                    drawLine(
                        color = TradingBorder.copy(alpha = 0.3f),
                        start = Offset(0f, y),
                        end = Offset(chartWidth, y),
                        strokeWidth = 1f
                    )
                    drawContext.canvas.nativeCanvas.apply {
                        val paint = android.graphics.Paint().apply {
                            color = android.graphics.Color.parseColor("#9CA3AF")
                            textSize = 22f
                            isAntiAlias = true
                        }
                        val label = if (isPercentageMode) {
                            val pct = ((v - initialBalance) / initialBalance) * 100.0
                            String.format(Locale.US, "%s%.1f%%", if (pct >= 0) "+" else "", pct)
                        } else {
                            String.format(Locale.US, "$%.1f", v)
                        }
                        drawText(label, chartWidth + 8f, y + 8f, paint)
                    }
                }

                // High Watermark (Peak Equity line)
                val peakPath = Path()
                points.forEachIndexed { i, p ->
                    val x = indexToX(i)
                    val y = valueToY(p.highWatermark)
                    if (i == 0) peakPath.moveTo(x, y) else peakPath.lineTo(x, y)
                }
                drawPath(path = peakPath, color = TradingGold.copy(alpha = 0.4f), style = Stroke(width = 1.5f))

                // Balance Curve (bold solid)
                val balancePath = Path()
                points.forEachIndexed { i, p ->
                    val x = indexToX(i)
                    val y = valueToY(p.balance)
                    if (i == 0) balancePath.moveTo(x, y) else balancePath.lineTo(x, y)
                }
                drawPath(
                    path = balancePath,
                    color = primaryCurveColor,
                    style = Stroke(width = 3.0f)
                )

                // Equity Curve (cyan line)
                if (curveType == ChartCurveType.EQUITY_AND_BALANCE) {
                    val equityPath = Path()
                    points.forEachIndexed { i, p ->
                        val x = indexToX(i)
                        val y = valueToY(p.equity)
                        if (i == 0) equityPath.moveTo(x, y) else equityPath.lineTo(x, y)
                    }
                    drawPath(
                        path = equityPath,
                        color = TradingCyan.copy(alpha = 0.85f),
                        style = Stroke(width = 2.0f)
                    )
                }
            }

            // Crosshair line when inspected
            selectedIndex?.let { idx ->
                val x = indexToX(idx)
                drawLine(
                    color = Color.White.copy(alpha = 0.7f),
                    start = Offset(x, 0f),
                    end = Offset(x, chartHeight),
                    strokeWidth = 1.5f
                )
            }
        }
    }
}
