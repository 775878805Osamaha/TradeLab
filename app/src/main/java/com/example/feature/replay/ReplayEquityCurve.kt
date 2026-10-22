package com.example.feature.replay

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * Lightweight Replay equity chart. Renders at most 400 points to keep the
 * results panel responsive even after a 5000-candle historical session.
 */
@Composable
fun ReplayEquityCurve(
    samples: List<ReplayEquitySample>,
    initialBalance: Double,
    modifier: Modifier = Modifier
) {
    val points = remember(samples) {
        if (samples.size <= 400) samples else {
            val last = samples.lastIndex
            (0 until 400).map { i -> samples[(i.toLong() * last / 399).toInt()] }
        }
    }
    if (points.isEmpty()) {
        Text("لا تتوفر نقاط ملكية بعد. شغّل Replay لعرض المنحنى.", fontSize = 12.sp)
        return
    }
    val values = points.map { it.equity }.filter { it.isFinite() }
    if (values.isEmpty()) return
    val low = min(initialBalance, values.minOrNull() ?: initialBalance)
    val high = max(initialBalance, values.maxOrNull() ?: initialBalance)
    val span = max(0.01, high - low)
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("منحنى الملكية", fontSize = 12.sp, fontWeight = FontWeight.Bold)
            Text(String.format(Locale.US, "$%.2f – $%.2f", low, high), fontSize = 10.sp)
        }
        Canvas(modifier = Modifier.fillMaxWidth().height(150.dp)) {
            val width = size.width
            val height = size.height
            val baselineY = height - ((initialBalance - low) / span).toFloat() * height
            drawLine(Color.Gray.copy(alpha = 0.45f), Offset(0f, baselineY), Offset(width, baselineY), strokeWidth = 1.dp.toPx())
            repeat(4) { line ->
                val y = height * (line + 1) / 5f
                drawLine(Color.Gray.copy(alpha = 0.15f), Offset(0f, y), Offset(width, y), strokeWidth = 1.dp.toPx())
            }
            val path = Path()
            points.forEachIndexed { i, sample ->
                val x = if (points.size == 1) 0f else width * i / (points.size - 1).toFloat()
                val y = height - ((sample.equity - low) / span).toFloat() * height
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            val rising = points.last().equity >= points.first().equity
            drawPath(path, if (rising) Color(0xFF16C784) else Color(0xFFEA3943), style = Stroke(width = 2.dp.toPx()))
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("شمعة #${points.first().candleIndex}", fontSize = 10.sp)
            Text("شمعة #${points.last().candleIndex}", fontSize = 10.sp)
        }
    }
}
