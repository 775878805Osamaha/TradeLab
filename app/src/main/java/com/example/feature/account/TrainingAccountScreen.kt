package com.example.feature.account

import com.example.ui.theme.*

import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.ui.res.stringResource
import com.example.R
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.feature.replay.ReplayViewModel
import java.util.Locale

private val TrainingCard get() = if (AppPalette.light) TradingCard else Color(0xFF131A24)
private val TrainingBorder get() = if (AppPalette.light) TradingBorder else Color(0xFF232C3A)
private val TrainingMuted get() = if (AppPalette.light) TradingTextSecondary else Color(0xFF8F98A8)
private val TrainingText get() = if (AppPalette.light) TradingTextPrimary else Color(0xFFE8ECF4)
private val TrainingProfit = Color(0xFF26A69A)
private val TrainingLoss = Color(0xFFEF5350)

@Composable
private fun AccountMetric(label: String, value: String, color: Color = TrainingText, modifier: Modifier = Modifier) {
    Card(modifier, shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = TrainingCard),
        border = BorderStroke(1.dp, TrainingBorder)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Text(label, color = TrainingMuted, fontSize = 12.sp)
            Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 22.sp,
                style = LocalTextStyle.current.copy(textDirection = TextDirection.Ltr))
        }
    }
}

@Composable
fun TrainingAccountScreen(viewModel: ReplayViewModel, onChart: () -> Unit, onSettings: () -> Unit = {}) {
    val state by viewModel.uiState.collectAsState()
    var amount by rememberSaveable { mutableStateOf("100") }
    var error by remember { mutableStateOf<String?>(null) }
    val started = state.openPositions.isNotEmpty() || state.closedTrades.isNotEmpty() || state.pendingOrders.isNotEmpty()
    fun money(value: Double) = String.format(Locale.US, "$%,.2f", value)
    fun pnlColor(value: Double) = if (value < 0) TrainingLoss else if (value > 0) TrainingProfit else TrainingText
    val realized = state.closedTrades.sumOf { it.netProfitLoss }
    val floating = state.openPositions.sumOf { it.netProfitLoss }
    val wins = state.closedTrades.count { it.netProfitLoss > 0 }
    val losses = state.closedTrades.count { it.netProfitLoss < 0 }
    val winRate = if (state.closedTrades.isEmpty()) "—" else String.format(Locale.US, "%.1f%%", wins * 100.0 / state.closedTrades.size)

    Column(Modifier.fillMaxSize().background(TradingBackground).verticalScroll(rememberScrollState()).padding(12.dp).testTag("account_screen"),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("حساب التدريب", color = TrainingText, style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.weight(1f).padding(vertical = 8.dp))
            IconButton(onClick = onSettings, modifier = Modifier.testTag("account_settings")) {
                Icon(Icons.Default.Settings, stringResource(R.string.title_settings), tint = TrainingText)
            }
        }
        Text("رصيد واحد • تداول على إعادة الشارت • نتائج محفوظة", color = TrainingMuted, fontSize = 12.sp)
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(containerColor = TrainingCard), border = BorderStroke(1.dp, TrainingBorder)) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("رصيد الحساب", color = TrainingMuted, fontSize = 13.sp)
                Text(money(state.currentBalance), color = TrainingText, fontWeight = FontWeight.Bold,
                    fontSize = 34.sp, style = LocalTextStyle.current.copy(textDirection = TextDirection.Ltr),
                    modifier = Modifier.testTag("training_balance"))
                HorizontalDivider(color = TrainingBorder)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically) {
                    Text("رصيد البداية", color = TrainingMuted, fontSize = 12.sp)
                    Text(money(state.initialBalance), color = TrainingText,
                        style = LocalTextStyle.current.copy(textDirection = TextDirection.Ltr))
                }
                Text("${state.openPositions.size} صفقات مفتوحة · ${state.closedTrades.size} مغلقة", color = TrainingMuted, fontSize = 12.sp)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            AccountMetric("قيمة الحساب", money(state.currentEquity), modifier = Modifier.weight(1f))
            AccountMetric("الربح العائم", money(floating), pnlColor(floating), Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            AccountMetric("الربح المحقق", money(realized), pnlColor(realized), Modifier.weight(1f))
            AccountMetric("معدل الفوز", winRate, modifier = Modifier.weight(1f))
        }
        Text("$wins رابحة · $losses خاسرة · ${state.pendingOrders.size} أوامر معلقة", color = TrainingMuted, fontSize = 12.sp)
        if (!started) {
            OutlinedTextField(amount, { amount = it; error = null }, label = { Text("رصيد البداية بالدولار") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true,
                textStyle = LocalTextStyle.current.copy(textDirection = TextDirection.Ltr),
                modifier = Modifier.fillMaxWidth().testTag("training_start_balance"))
            Button(onClick = {
                val value = amount.toDoubleOrNull()
                if (value == null || !viewModel.configureTrainingBalance(value)) error = "أدخل مبلغًا موجبًا صالحًا قبل بدء التداول"
                else onChart()
            }, enabled = !state.isLoading, shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth().testTag("training_start")) { Text("بدء التدريب بهذا الرصيد") }
        } else {
            Button(onClick = onChart, shape = RoundedCornerShape(10.dp), modifier = Modifier.fillMaxWidth()) { Text("متابعة التدريب على الشارت") }
        }
        error?.let { Text(it, color = TrainingLoss) }
        Text("اضغط خط الصفقة على الشارت للإغلاق أو تعديل الوقف والهدف أو إغلاق جزء منها.", color = TrainingMuted, fontSize = 12.sp)
    }
}
