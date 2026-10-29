package com.example.feature.chart

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import com.example.core.model.Tick
import com.example.core.market.VerifiedMarketQuote

internal object ChartPriceAlertRule {
    fun reached(tick: Tick?,symbol: String,target: Double,above: Boolean,replay: Boolean,now: Long): Boolean {
        if(replay || !target.isFinite() || target<=0 || !VerifiedMarketQuote.isVerified(tick,symbol,now)) return false
        return if(above) tick!!.bid>=target else tick!!.bid<=target
    }
}

/** Foreground chart alert; does not claim a background notification service. */
@Composable
internal fun ChartPriceAlert(symbol: String,tick: Tick?,replay: Boolean,show: Boolean,onDismiss: () -> Unit) {
    val context=LocalContext.current
    val prefs=remember(context) { context.getSharedPreferences("chart_price_alerts",0) }
    var target by remember(symbol) { mutableStateOf(prefs.getString("$symbol.target","") ?: "") }
    var above by remember(symbol) { mutableStateOf(prefs.getBoolean("$symbol.above",true)) }
    var enabled by remember(symbol) { mutableStateOf(prefs.getBoolean("$symbol.enabled",false)) }
    var fired by remember(symbol) { mutableStateOf<String?>(null) }
    fun save() { prefs.edit().putString("$symbol.target",target).putBoolean("$symbol.above",above).putBoolean("$symbol.enabled",enabled).apply() }
    LaunchedEffect(tick,symbol,replay,enabled) {
        if(enabled && ChartPriceAlertRule.reached(tick,symbol,target.toDoubleOrNull() ?: Double.NaN,above,replay,System.currentTimeMillis())) {
            enabled=false;save();fired="$symbol وصل إلى ${tick!!.bid}"
        }
    }
    if(show) AlertDialog(onDismissRequest=onDismiss,title={Text("تنبيه سعر $symbol")},text={Column {
        Text("يعمل أثناء فتح شارت هذا الرمز فقط، باستخدام سعر BID المباشر. لا يعمل أثناء الريبلاي أو عند إغلاق التطبيق.")
        OutlinedTextField(target,{target=it;enabled=false;save()},label={Text("السعر")},singleLine=true)
        TextButton(onClick={above=!above;enabled=false;save()}) { Text(if(above) "عند السعر أو أعلى" else "عند السعر أو أقل") }
        Text(if(enabled) "التنبيه مفعّل" else "التنبيه متوقف")
    }},confirmButton={TextButton(enabled=target.toDoubleOrNull()?.let { it.isFinite() && it>0 }==true,onClick={enabled=true;save();onDismiss()}) {Text("تفعيل")}},
        dismissButton={TextButton(onClick={enabled=false;save();onDismiss()}) {Text("إيقاف وإغلاق")}})
    fired?.let { message -> AlertDialog(onDismissRequest={fired=null},title={Text("تنبيه السعر")},text={Text(message)},confirmButton={TextButton(onClick={fired=null}) {Text("حسنًا")}}) }
}
