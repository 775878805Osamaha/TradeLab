package com.example.feature.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.market.DefaultMarketDataProvider
import com.example.TradeLabApplication
import com.example.core.model.ProviderConnectionStatus
import com.example.ui.components.DataSourceBadge
import com.example.ui.theme.*
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    provider: DefaultMarketDataProvider,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val diag by provider.diagnosticInfo.collectAsState()
    val context = LocalContext.current
    val cTrader = (context.applicationContext as TradeLabApplication).cTrader
    val cTraderStatus by cTrader.status.collectAsState()
    val cTraderAccounts by cTrader.accounts.collectAsState()
    val selectedCTraderAccount by cTrader.selectedAccount.collectAsState()
    var linking by remember { mutableStateOf(false) }
    var selectingAccount by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val sdf = remember { SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") } }

    Scaffold(
        modifier = modifier.testTag("settings_screen"),
        topBar = {
            TopAppBar(
                title = { Text(androidx.compose.ui.res.stringResource(com.example.R.string.title_settings), fontSize = 17.sp, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = TradingBackground)
            )
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            contentPadding = PaddingValues(bottom = 24.dp)
        ) {
            item { AppearanceSettings() }
            item {
                Card(Modifier.fillMaxWidth().testTag("ctrader_settings_card")) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("cTrader • الفوركس والذهب", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        Text(cTraderStatus, fontSize = 12.sp, color = TradingTextSecondary)
                        Text("كل مستخدم يربط حسابه الخاص بصلاحية القراءة فقط. جميع الصفقات داخل TradeLab تجريبية.",
                            fontSize = 12.sp, color = TradingTextSecondary)
                        Button(
                            onClick = {
                                try {
                                    val url = cTrader.beginAuthorization()
                                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                } catch (error: Exception) { cTrader.reportError("لم يتم فتح صفحة التفويض") }
                            },
                            modifier = Modifier.fillMaxWidth().testTag("ctrader_connect_button"),
                            colors = ButtonDefaults.buttonColors(containerColor = TradingAccent)
                        ) { Text(if (cTrader.isLinked()) "إعادة ربط cTrader" else "ربط حساب cTrader") }
                        if (cTrader.isLinked()) {
                            TextButton(onClick = { scope.launch {
                                linking = true
                                try { cTrader.refreshAccounts() } catch (_: Exception) { }
                                finally { linking = false }
                            } }, enabled = !linking) { Text("تحديث الحسابات والرموز") }
                            if (cTraderAccounts.isNotEmpty()) {
                                var expanded by remember { mutableStateOf(false) }
                                Box {
                                    OutlinedButton(onClick = { expanded = true }, enabled = !selectingAccount,
                                        modifier = Modifier.fillMaxWidth().testTag("ctrader_account_selector")) {
                                        Text("حساب cTrader: $selectedCTraderAccount")
                                    }
                                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                                        cTraderAccounts.forEach { account ->
                                            DropdownMenuItem(text = {
                                                Text("${account.id} • ${if (account.isLive) "Live" else "Demo"} • ${account.broker}")
                                            }, onClick = {
                                                expanded = false
                                                scope.launch {
                                                    selectingAccount = true
                                                    try {
                                                        cTrader.selectAccount(account.id)
                                                        provider.invalidateForexQuotes()
                                                    } catch (error: Exception) {
                                                        cTrader.reportError(error.message ?: "فشل اختيار الحساب")
                                                    } finally { selectingAccount = false }
                                                }
                                            })
                                        }
                                    }
                                }
                            }
                            OutlinedButton(onClick = {
                                cTrader.logout()
                                provider.invalidateForexQuotes()
                            }, modifier = Modifier.fillMaxWidth().testTag("ctrader_logout_button")) {
                                Text("فصل حساب cTrader")
                            }
                        }
                    }
                }
            }
            // Live Connectivity & Quality Diagnostic Card (Section 36)
            item {
                Card(
                    modifier = Modifier.fillMaxWidth().testTag("market_diagnostic_card"),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(text = "حالة اتصال مزود البيانات", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                            DataSourceBadge(sourceType = diag.dataSourceType)
                        }

                        HorizontalDivider(color = TradingBorder)

                        DiagnosticRow("اسم المزود", diag.providerName)
                        DiagnosticRow("حالة الاتصال", diag.connectionStatus.displayName, isStatus = true, status = diag.connectionStatus)
                        DiagnosticRow("آخر تحديث (UTC)", sdf.format(Date(diag.lastUpdateTimestamp)))
                        DiagnosticRow("زمن الوصول التقريبي", "${diag.approximateLatencyMs} ms")
                        DiagnosticRow("محاولات إعادة الاتصال", "${diag.reconnectCount}")
                        DiagnosticRow("أخطاء سلامة البيانات", "${diag.validationErrorsCount}", isError = diag.validationErrorsCount > 0)
                        Text("آخر نتيجة HTTP من Binance", fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        Text(diag.lastHttpDiagnostic, fontSize = 11.sp, color = TradingTextSecondary)
                        DiagnosticRow("حالة حداثة البيانات", if (diag.isStale) "قديمة / متأخرة (Stale)" else "طازجة ولحظية (Fresh)", isError = diag.isStale)

                        Spacer(modifier = Modifier.height(4.dp))

                        Button(
                            onClick = {
                                scope.launch {
                                    provider.disconnect()
                                    provider.connect()
                                }
                            },
                            modifier = Modifier.fillMaxWidth().testTag("reconnect_provider_btn"),
                            colors = ButtonDefaults.buttonColors(containerColor = TradingAccent),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(6.dp))
                            Text("إعادة تشغيل الاتصال والتحقق", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }

            // Architecture & Compliance Card
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Shield, contentDescription = null, tint = TradingCyan)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(text = "ميثاق الأمان والبيانات الحقيقية", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "• BTCUSDT و ETHUSDT متصلان مباشرة ببيانات السوق اللحظية عبر Binance Public WebSocket.\n" +
                                    "• XAUUSD وأزواج الفوركس: cTrader فقط من حساب المستخدم بعد تسجيل الدخول، دون مزود بديل.\n" +
                                    "• التطبيق لا يتصل بأي وسيط مالي، ولا يدعم التداول بأموال حقيقية نهائياً. كل الأوامر افتراضية 100%.",
                            fontSize = 12.sp,
                            color = TradingTextSecondary,
                            lineHeight = 18.sp
                        )
                    }
                }
            }

        }
    }
}

@Composable
private fun DiagnosticRow(
    label: String,
    value: String,
    isStatus: Boolean = false,
    status: ProviderConnectionStatus? = null,
    isError: Boolean = false
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = label, fontSize = 12.sp, color = TradingTextSecondary)
        if (isStatus && status != null) {
            val color = when (status) {
                ProviderConnectionStatus.CONNECTED -> TradingPositive
                ProviderConnectionStatus.CONNECTING, ProviderConnectionStatus.RECONNECTING -> TradingGold
                ProviderConnectionStatus.DEGRADED -> Color(0xFFF97316)
                ProviderConnectionStatus.DISCONNECTED, ProviderConnectionStatus.ERROR -> TradingNegative
            }
            Text(text = value, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = color)
        } else {
            Text(
                text = value,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (isError) TradingNegative else TradingTextPrimary
            )
        }
    }
}
