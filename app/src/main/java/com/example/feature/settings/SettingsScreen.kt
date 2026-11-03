package com.example.feature.settings

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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.market.DefaultMarketDataProvider
import com.example.data.repository.MarketDataRepository
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
    repository: MarketDataRepository,
    onBack: () -> Unit,
    cTraderCallbackStatus: String? = null,
    modifier: Modifier = Modifier
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val diag by provider.diagnosticInfo.collectAsState()
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    val cTrader = com.example.feature.ctrader.CTraderAuthorization
    val activeCTraderAccount by repository.cTraderAccount.collectAsState()
    var enablingCTrader by remember { mutableStateOf(false) }
    var sourceChangeMessage by remember { mutableStateOf<String?>(null) }
    var accountStatus by remember { mutableStateOf<String?>(null) }
    var goldCheckStatus by remember { mutableStateOf<String?>(null) }
    var goldCheckRunning by remember { mutableStateOf(false) }
    var gatewayCheck by remember { mutableStateOf<com.example.feature.ctrader.CTraderAuthorization.GatewayCheck?>(null) }
    var gatewayChecking by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        gatewayCheck = cTrader.checkGateway()
        gatewayChecking = false
    }
    LaunchedEffect(cTraderCallbackStatus) {
        accountStatus = if (cTrader.isLinked(context)) cTrader.accountSummary(context) else null
    }
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
            // Keep normal TradeLab use completely independent of hosting and cTrader login.
            // Display this optional integration only when a tested HTTPS gateway is configured.
            if (cTrader.isConfigured) item {
                Card(
                    modifier = Modifier.fillMaxWidth().testTag("ctrader_oauth_card"),
                    colors = CardDefaults.cardColors(containerColor = TradingCard)
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("ربط cTrader — قراءة فقط", fontWeight = FontWeight.Bold)
                        Text("سيفتح تسجيل الدخول في متصفح الهاتف. لا يمكن لـ TradeLab تنفيذ صفقات حقيقية بهذه الصلاحية.",
                            fontSize = 12.sp, color = TradingTextSecondary)
                        Button(
                            modifier = Modifier.fillMaxWidth().testTag("ctrader_browser_login"),
                            enabled = gatewayCheck?.authEnabled == true,
                            onClick = {
                                val url = cTrader.authorizationUrl(context)
                                if (url != null) {
                                    context.startActivity(android.content.Intent(
                                        android.content.Intent.ACTION_VIEW, url
                                    ).addCategory(android.content.Intent.CATEGORY_BROWSABLE))
                                }
                            }
                        ) { Text("تسجيل الدخول إلى cTrader") }
                        OutlinedButton(
                            modifier = Modifier.fillMaxWidth().testTag("ctrader_gateway_health_check"),
                            enabled = !gatewayChecking,
                            onClick = {
                                gatewayChecking = true
                                scope.launch {
                                    gatewayCheck = cTrader.checkGateway()
                                    gatewayChecking = false
                                }
                            }
                        ) { Text(if(gatewayChecking) "جارٍ فحص اتصال الخدمة..." else "فحص اتصال خدمة cTrader") }
                        gatewayCheck?.let { state ->
                            Text(state.message, fontSize = 12.sp,
                                color = if(state.reachable) TradingTextSecondary else TradingGold)
                        }
                        if(cTraderCallbackStatus != null) {
                            Text(cTraderCallbackStatus, fontSize = 12.sp, color = TradingGold)
                        }
                        if (accountStatus != null) {
                            Text(accountStatus!!, fontSize = 12.sp, color = TradingCyan)
                        }
                        if (cTrader.isLinked(context) && cTrader.isConfigured) {
                            OutlinedButton(
                                enabled = !goldCheckRunning,
                                modifier = Modifier.fillMaxWidth().testTag("ctrader_gold_smoke_test"),
                                onClick = {
                                    goldCheckRunning = true
                                    scope.launch {
                                        goldCheckStatus = try {
                                            com.example.feature.ctrader.CTraderReadOnlyMarketApi(context).goldCheck()
                                        } catch (_: Exception) {
                                            "لم تصل بيانات ذهب موثوقة من cTrader الآن. تحقق من حساب الوسيط والاتصال."
                                        }
                                        goldCheckRunning = false
                                    }
                                }
                            ) {
                                Text(if (goldCheckRunning) "جارٍ اختبار بيانات الذهب…" else "اختبار السعر الحقيقي للذهب XAUUSD")
                            }
                            if(goldCheckStatus!=null)Text(goldCheckStatus!!,fontSize=12.sp,color=TradingTextSecondary)
                        }
                        if (cTrader.isLinked(context)) {
                            if(activeCTraderAccount == null) {
                                Button(
                                    modifier=Modifier.fillMaxWidth().testTag("ctrader_enable_chart"),
                                    enabled=!enablingCTrader && gatewayCheck?.authEnabled==true,
                                    onClick={
                                        enablingCTrader=true
                                        sourceChangeMessage=null
                                        scope.launch {
                                            sourceChangeMessage=try {
                                                repository.enableCTraderGold()
                                            } catch(e:kotlinx.coroutines.CancellationException) {
                                                throw e
                                            } catch(e:Exception) {
                                                "لم يتغير المصدر: "+(e.message ?: "تعذر التحقق من سعر الذهب والشموع")
                                            }
                                            enablingCTrader=false
                                        }
                                    }
                                ) { Text(if(enablingCTrader) "جارٍ فحص السعر والشموع..." else "اعتماد cTrader للشارت والريبلاي") }
                                Text("لا يتغير مصدر الذهب والفوركس قبل فحص سعر Bid/Ask حديث وشموع حقيقية مغلقة من الوسيط.",
                                    fontSize=11.sp,color=TradingTextSecondary)
                            } else {
                                Text("مصدر الذهب والفوركس المحدد: cTrader — حساب "+activeCTraderAccount,
                                    fontSize=12.sp,color=TradingCyan)
                                OutlinedButton(
                                    modifier=Modifier.fillMaxWidth().testTag("ctrader_disable_chart"),
                                    onClick={
                                        repository.disableCTrader()
                                        sourceChangeMessage="تم الرجوع لمصدر الذهب والفوركس السابق"
                                    }
                                ) { Text("الرجوع إلى المصدر السابق") }
                            }
                        }
                        sourceChangeMessage?.let {
                            Text(it,fontSize=12.sp,color=TradingGold)
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
                            Text(text = "حالة مزود Binance / Biquote", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                            DataSourceBadge(sourceType = diag.dataSourceType)
                        }

                        HorizontalDivider(color = TradingBorder)

                        Text(if(activeCTraderAccount!=null)
                            "الشارت للذهب والفوركس يستخدم cTrader؛ مؤشرات الاتصال التالية تخص Binance/Biquote فقط."
                            else "مصدر الشارت الأساسي Binance/Biquote؛ cTrader لا يصبح المصدر قبل اعتماده.",
                            fontSize=11.sp,color=TradingTextSecondary)
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

            item { HistorySettingsCard() }

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
                                    (if(activeCTraderAccount != null)
                                        "• الذهب والفوركس يعرضان أسعار cTrader الموثقة من حسابك فقط، ولا يتم دمجها بمصادر أخرى.\n"
                                    else
                                        "• الذهب والفوركس يستخدمان المصدر السابق؛ تسجيل دخول cTrader وحده لا يبدّل الشارت.\n") +
                                    "• اتصال cTrader بصلاحية القراءة فقط. كل الأوامر والصفقات داخل TradeLab افتراضية 100%.",
                            fontSize = 12.sp,
                            color = TradingTextSecondary,
                            lineHeight = 18.sp
                        )
                    }
                }
            }

            // Custom Provider / API Keys Documentation Card
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Key, contentDescription = null, tint = TradingGold)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(text = "ربط مزود بيانات خاص (API)", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "تم بناء معمارية التطبيق خلف الواجهة المجردة MarketDataProvider و HistoricalDataProvider.\n" +
                                    "تم تجهيز ربط cTrader عبر خدمة HTTPS آمنة. مفتاح Client Secret يبقى على الخادم ولا يُحفظ في APK؛ ويمكن استخدام Twelve Data يدويًا لمصدر تاريخي بديل.",
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
