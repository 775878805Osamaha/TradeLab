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
    val diag by provider.diagnosticInfo.collectAsState()
    val scope = rememberCoroutineScope()
    val sdf = remember { SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") } }

    Scaffold(
        modifier = modifier.testTag("settings_screen"),
        topBar = {
            TopAppBar(
                title = { Text("لوحة جودة واتصال بيانات السوق", fontSize = 17.sp, fontWeight = FontWeight.Bold) },
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
            item { HistorySettingsCard() }

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
                                    androidx.compose.ui.res.stringResource(com.example.R.string.history_source_note) + "\n" +
                                    "• التطبيق لا يتصل بأي وسيط مالي، ولا يدعم التداول بأموال حقيقية نهائياً. كل الأوامر افتراضية 100%.",
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
                                    "لإضافة مفاتيح مزود مدفوع مثل TwelveData أو Polygon أو Interactive Brokers، يتم إدخال المفاتيح بشكل آمن عبر لوحة الأسرار (Secrets panel) أو ملف .env دون تضمينها في الكود.",
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
