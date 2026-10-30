package com.example.feature.chart

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.model.Timeframe
import com.example.ui.theme.*

/** Reference pixels: 864 x 1536. Bottom chart strip is 96px (44dp at 400dp width). */
@Composable
internal fun ChartBottomStrip(
    symbol: String,
    timeframe: Timeframe,
    replayActive: Boolean,
    onSymbol: () -> Unit,
    onTimeframe: (Timeframe) -> Unit,
    onReplay: () -> Unit,
    onIndicators: () -> Unit,
    onDrawing: () -> Unit,
    onMore: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val context = LocalContext.current
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Row(
            Modifier.fillMaxWidth().height(44.dp).background(TradingChartBackground)
                .testTag("chart_bottom_strip"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            IconButton(onClick = {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, "TradeLab · $symbol · ${timeframe.displayName}")
                }
                context.startActivity(Intent.createChooser(send, "مشاركة الشارت"))
            }, modifier = Modifier.size(36.dp).testTag("chart_share")) {
                Icon(Icons.Default.IosShare, "مشاركة", tint = TradingTextPrimary, modifier = Modifier.size(23.dp))
            }
            IconButton(onClick = onMore, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Default.MoreHoriz, "المزيد", tint = TradingTextPrimary)
            }
            IconButton(onClick = onIndicators, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Default.MultilineChart, "المؤشرات", tint = TradingTextPrimary)
            }
            IconButton(onClick = onDrawing, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Default.Edit, "أدوات الرسم", tint = TradingTextPrimary)
            }
            IconButton(onClick = onReplay, modifier = Modifier.size(32.dp).testTag("chart_bottom_replay")) {
                Icon(Icons.Default.ReplayCircleFilled, if (replayActive) "إنهاء الإعادة" else "إعادة العرض داخل الشارت",
                    tint = if (replayActive) Color(0xFF2962FF) else TradingTextPrimary,
                    modifier = Modifier.size(21.dp))
            }
            Box {
                Row(Modifier.clickable { expanded = true }.height(44.dp).testTag("chart_bottom_timeframe"),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(timeframe.arabicLabel(), color = TradingTextPrimary, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    Icon(Icons.Default.KeyboardArrowDown, "الفاصل الزمني", tint = TradingTextPrimary, modifier = Modifier.size(16.dp))
                }
                DropdownMenu(expanded, { expanded = false }) {
                    Timeframe.entries.forEach { tf ->
                        DropdownMenuItem(text = { Text(tf.displayName) }, onClick = { expanded = false; onTimeframe(tf) })
                    }
                }
            }
            Column(Modifier.clickable(onClick = onSymbol).height(44.dp).padding(horizontal = 4.dp)
                .testTag("chart_bottom_symbol"), verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.End) {
                Text(symbol, color = TradingTextPrimary, fontWeight = FontWeight.Bold, fontSize = 14.sp, maxLines = 1)
                Text(if (symbol == "XAUUSD") "GOLD" else symbol.removeSuffix("USDT").removeSuffix("USD"),
                    color = TradingTextSecondary, fontSize = 11.sp, maxLines = 1)
            }
        }
    }
}

internal fun Timeframe.arabicLabel(): String = when {
    minutes < 60 -> "$minutes دق"
    minutes < 1440 -> "${minutes / 60} س"
    minutes < 10080 -> "1 يوم"
    else -> "1 أسبوع"
}
