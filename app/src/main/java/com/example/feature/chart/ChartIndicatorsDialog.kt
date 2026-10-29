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
    val prefs = androidx.compose.ui.platform.LocalContext.current.getSharedPreferences("chart_workspace",0)
    var periods by remember { mutableStateOf(listOf(currentSettings.smaPeriod,currentSettings.emaPeriod,
        currentSettings.bollingerPeriod,currentSettings.rsiPeriod,currentSettings.macdFast,currentSettings.macdSlow,
        currentSettings.macdSignal,currentSettings.atrPeriod).map { it.toString() }) }
    var deviation by remember { mutableStateOf(currentSettings.bollingerStdDev.toString()) }
    val values = periods.map { it.toIntOrNull() }
    val valid = values.all { it != null && it in 2..500 } &&
        (values[4] ?: 0) < (values[5] ?: 0) && deviation.toDoubleOrNull()?.let { it.isFinite() && it in 0.1..10.0 } == true
    fun applyPeriods(): IndicatorSettings = settings.copy(smaPeriod=values[0]!!,emaPeriod=values[1]!!,
        bollingerPeriod=values[2]!!,rsiPeriod=values[3]!!,macdFast=values[4]!!,macdSlow=values[5]!!,
        macdSignal=values[6]!!,atrPeriod=values[7]!!,bollingerStdDev=deviation.toDouble())
    fun restore(value: IndicatorSettings) {
        settings=value
        periods=listOf(value.smaPeriod,value.emaPeriod,value.bollingerPeriod,value.rsiPeriod,
            value.macdFast,value.macdSlow,value.macdSignal,value.atrPeriod).map { it.toString() }
        deviation=value.bollingerStdDev.toString()
    }


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
                    paramText = "السريع: ${periods[4]} • البطيء: ${periods[5]} • الإشارة: ${periods[6]}",
                    onToggle = { settings = settings.copy(isMacdEnabled = !settings.isMacdEnabled) }
                )

                IndicatorToggleRow(
                    title = "متوسط المدى الحقيقي (ATR)",
                    enabled = settings.isAtrEnabled,
                    paramText = "الفترة: ${settings.atrPeriod} لقياس التذبذب",
                    onToggle = { settings = settings.copy(isAtrEnabled = !settings.isAtrEnabled) }
                )

                HorizontalDivider()
                Text("فترات المؤشرات",fontWeight=FontWeight.Bold)
                listOf("SMA","EMA","Bollinger","RSI","MACD سريع","MACD بطيء","MACD إشارة","ATR").forEachIndexed { index,label ->
                    OutlinedTextField(periods[index],{ value -> periods=periods.toMutableList().also { it[index]=value } },
                        label={Text(label)},singleLine=true,isError=values[index]?.let { it in 2..500 } != true,
                        keyboardOptions=androidx.compose.foundation.text.KeyboardOptions(keyboardType=androidx.compose.ui.text.input.KeyboardType.Number))
                }
                OutlinedTextField(deviation,{deviation=it},label={Text("انحراف بولينجر")},singleLine=true)
                if(!valid) Text("الفترات من 2 إلى 500؛ سريع MACD أقل من البطيء؛ الانحراف من 0.1 إلى 10.",color=MaterialTheme.colorScheme.error)
                Row {
                    TextButton(onClick={restore(IndicatorSettings(isEmaEnabled=false))}) { Text("إعادة الضبط") }
                    TextButton(enabled=valid,onClick={ChartWorkspaceSettings.save(prefs,"indicator_template",applyPeriods())}) { Text("حفظ قالب") }
                    TextButton(onClick={restore(ChartWorkspaceSettings.load(prefs,"indicator_template"))}) { Text("استعادة قالب") }
                }
                Spacer(modifier = Modifier.height(6.dp))

                Button(
                    enabled = valid,
                    onClick = {
                        onSaveSettings(applyPeriods())
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
