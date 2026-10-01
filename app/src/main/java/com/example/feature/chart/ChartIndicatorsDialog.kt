package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.example.feature.chart.model.IndicatorSettings
import com.example.ui.theme.*

@Composable
fun ChartIndicatorsDialog(
    currentSettings: IndicatorSettings,
    onSaveSettings: (IndicatorSettings) -> Unit,
    onDismiss: () -> Unit
) {
    var settings by remember { mutableStateOf(currentSettings) }

    Dialog(onDismissRequest = onDismiss) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = TradingCard),
            border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
        ) {
            Column(
                modifier = Modifier
                    .padding(18.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(text = "إعدادات المؤشرات الفنية", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "إغلاق")
                    }
                }

                HorizontalDivider(color = TradingBorder)

                // Overlays section
                Text(text = "مؤشرات الشارت الرئيسي (Overlays)", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = TradingAccent)

                IndicatorToggleRow(
                    title = "المتوسط المتحرك البسيط (SMA)",
                    enabled = settings.isSmaEnabled,
                    paramText = "الفترة: ${settings.smaPeriod}",
                    onToggle = { settings = settings.copy(isSmaEnabled = !settings.isSmaEnabled) }
                )

                IndicatorToggleRow(
                    title = "المتوسط المتحرك الأسي (EMA)",
                    enabled = settings.isEmaEnabled,
                    paramText = "الفترة: ${settings.emaPeriod}",
                    onToggle = { settings = settings.copy(isEmaEnabled = !settings.isEmaEnabled) }
                )

                IndicatorToggleRow(
                    title = "نطاقات بولينجر (Bollinger Bands)",
                    enabled = settings.isBollingerEnabled,
                    paramText = "الفترة: ${settings.bollingerPeriod} • الانحراف: ${settings.bollingerStdDev}",
                    onToggle = { settings = settings.copy(isBollingerEnabled = !settings.isBollingerEnabled) }
                )

                IndicatorToggleRow(
                    title = "متوسط السعر المرجح بالحجم (VWAP)",
                    enabled = settings.isVwapEnabled,
                    paramText = "حساب تراكمي لحجم التداول",
                    onToggle = { settings = settings.copy(isVwapEnabled = !settings.isVwapEnabled) }
                )

                HorizontalDivider(color = TradingBorder)

                // Subpanels section
                Text(text = "مؤشرات اللوحة السفلية (Subpanels)", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = TradingCyan)

                IndicatorToggleRow(
                    title = "مؤشر القوة النسبية (RSI)",
                    enabled = settings.isRsiEnabled,
                    paramText = "الفترة: ${settings.rsiPeriod} (70/30)",
                    onToggle = { settings = settings.copy(isRsiEnabled = !settings.isRsiEnabled) }
                )

                IndicatorToggleRow(
                    title = "مؤشر الماكد (MACD)",
                    enabled = settings.isMacdEnabled,
                    paramText = "السريع: 12 • البطيء: 26 • الإشارة: 9",
                    onToggle = { settings = settings.copy(isMacdEnabled = !settings.isMacdEnabled) }
                )

                IndicatorToggleRow(
                    title = "متوسط المدى الحقيقي (ATR)",
                    enabled = settings.isAtrEnabled,
                    paramText = "الفترة: ${settings.atrPeriod} لقياس التذبذب",
                    onToggle = { settings = settings.copy(isAtrEnabled = !settings.isAtrEnabled) }
                )

                Spacer(modifier = Modifier.height(6.dp))

                Button(
                    onClick = {
                        onSaveSettings(settings)
                        onDismiss()
                    },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = TradingAccent)
                ) {
                    Text("حفظ وتطبيق المؤشرات", fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun IndicatorToggleRow(
    title: String,
    enabled: Boolean,
    paramText: String,
    onToggle: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = TradingTextPrimary)
            Text(text = paramText, fontSize = 10.sp, color = TradingTextSecondary)
        }
        Switch(
            checked = enabled,
            onCheckedChange = { onToggle() },
            colors = SwitchDefaults.colors(checkedThumbColor = TradingAccent, checkedTrackColor = TradingAccent.copy(alpha = 0.5f))
        )
    }
}
