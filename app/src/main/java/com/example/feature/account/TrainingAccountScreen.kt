package com.example.feature.account

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.feature.replay.ReplayViewModel
import java.util.Locale

@Composable
fun TrainingAccountScreen(viewModel:ReplayViewModel,onChart:()->Unit) {
    val state by viewModel.uiState.collectAsState()
    var amount by rememberSaveable { mutableStateOf("100") }
    var error by remember { mutableStateOf<String?>(null) }
    val started=state.openPositions.isNotEmpty() || state.closedTrades.isNotEmpty() || state.pendingOrders.isNotEmpty()
    fun money(v:Double)=String.format(Locale.US,"$%,.2f",v)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).testTag("account_screen"),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        Text("حساب التدريب",style=MaterialTheme.typography.headlineSmall)
        Text("حدد رصيد البداية، ثم نفّذ صفقاتك على إعادة الشارت. تُسجّل الصفقات والنتائج في هذا الحساب.")
        Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
            Text("الرصيد: ${money(state.currentBalance)}",style=MaterialTheme.typography.headlineMedium)
            Text("قيمة الحساب: ${money(state.currentEquity)}")
            Text("رصيد البداية: ${money(state.initialBalance)}")
            Text("${state.openPositions.size} صفقات مفتوحة · ${state.closedTrades.size} مغلقة")
            Text("الربح المحقق: ${money(state.closedTrades.sumOf{it.netProfitLoss})}")
            Text("الربح العائم: ${money(state.openPositions.sumOf{it.profitLoss})}")
        } }
        if(!started) {
            OutlinedTextField(amount,{amount=it;error=null},label={Text("رصيد البداية بالدولار")},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal),singleLine=true,modifier=Modifier.fillMaxWidth().testTag("training_start_balance"))
            Button(onClick={val value=amount.toDoubleOrNull();if(value==null || !viewModel.configureTrainingBalance(value))error="أدخل مبلغًا موجبًا صالحًا قبل بدء التداول" else onChart()},enabled=!state.isLoading,modifier=Modifier.fillMaxWidth().testTag("training_start")){Text("بدء التدريب بهذا الرصيد")}
        }
        error?.let{Text(it,color=MaterialTheme.colorScheme.error)}
        Button(onClick=onChart,modifier=Modifier.fillMaxWidth()){Text("الانتقال إلى الشارت")}
        Text("يمكنك إغلاق الصفقة، وضع وقف وهدف أو الإغلاق الجزئي من خط الصفقة على الشارت.")
    }
}
