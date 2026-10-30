package com.example.feature.chart

import com.example.ui.theme.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Reference header: three 28dp controls, 7dp gaps and a 50dp quote-unit field. */
@Composable
internal fun ChartHeaderControls(symbol: String, replayActive: Boolean,
    onReset: () -> Unit, onReplay: () -> Unit, onDetails: () -> Unit) {
    var quoteInfoExpanded by remember { mutableStateOf(false) }
    // A quote-unit label, not an invented currency conversion or USD equivalence.
    val quote = listOf("USDT", "USD", "JPY", "GBP", "EUR", "CHF", "CAD", "AUD", "NZD", "BTC", "ETH")
        .firstOrNull { symbol.endsWith(it) } ?: symbol
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            HeaderAction(Icons.Default.North, "إعادة ضبط الشارت", false, onReset)
            HeaderAction(Icons.Default.ReplayCircleFilled, "إعادة العرض", replayActive, onReplay)
            HeaderAction(Icons.Default.Fullscreen, "عرض التفاصيل", false, onDetails)
            Box {
                Surface(Modifier.size(width = 50.dp, height = 30.dp).clickable { quoteInfoExpanded = true },
                    shape = RoundedCornerShape(4.dp), color = TradingChartBackground,
                    border = BorderStroke(.7.dp, TradingBorder)) {
                    Row(Modifier.padding(horizontal = 5.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(quote, color = TradingTextPrimary, fontSize = 10.sp)
                        Icon(Icons.Default.KeyboardArrowDown, "عملة التسعير", tint = TradingTextSecondary, modifier = Modifier.size(13.dp))
                    }
                }
                DropdownMenu(quoteInfoExpanded, { quoteInfoExpanded = false }) {
                    DropdownMenuItem(text = { Text("$quote · عملة التسعير الأصلية") },
                        leadingIcon = { Icon(Icons.Default.Check, contentDescription = null) },
                        onClick = { quoteInfoExpanded = false })
                }
            }
        }
    }
}

@Composable
private fun HeaderAction(icon: ImageVector, label: String, active: Boolean, onClick: () -> Unit) {
    Surface(Modifier.size(28.dp).clickable(onClick = onClick), shape = RoundedCornerShape(4.dp),
        color = TradingChartBackground, border = BorderStroke(.7.dp, if (active) Color(0xFF2962FF) else TradingBorder)) {
        Box(contentAlignment = Alignment.Center) {
            Icon(icon, label, tint = if (active) Color(0xFF2962FF) else TradingTextPrimary, modifier = Modifier.size(18.dp))
        }
    }
}
