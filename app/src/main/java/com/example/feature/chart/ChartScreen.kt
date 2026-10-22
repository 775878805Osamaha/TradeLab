package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.market.DefaultSymbols
import com.example.core.model.DataSourceType
import com.example.core.model.OrderSide
import com.example.core.model.Timeframe
import com.example.feature.chart.model.DrawingTool
import com.example.feature.replay.ReplayViewModel
import com.example.feature.results.TradeDetailDialog
import com.example.ui.components.CandlestickChart
import com.example.ui.components.ChartDisplayStyle
import com.example.ui.components.DataSourceBadge
import com.example.ui.theme.*
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChartScreen(
    viewModel: ChartViewModel,
    replayViewModel: ReplayViewModel,
    onNavigateToReplay: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val replayState by replayViewModel.uiState.collectAsState()
    var isEmbeddedReplay by remember { mutableStateOf(false) }
    var showSymbolSheet by remember { mutableStateOf(false) }
    var showToolsMenu by remember { mutableStateOf(false) }
    var showReplayDetails by remember { mutableStateOf(false) }
    var showChartExtras by remember { mutableStateOf(false) }
    var showIndicatorsDialog by remember { mutableStateOf(false) }
    var chartDisplayStyle by remember { mutableStateOf(ChartDisplayStyle.CANDLES) }
    var immersiveChart by remember { mutableStateOf(true) }
    var showHistoricalSourceDialog by remember { mutableStateOf(false) }
    var historicalApiKeyInput by remember { mutableStateOf("") }

    // Refresh the freshness indicator even when the market stream stops emitting.
    var quoteClock by remember { mutableLongStateOf(System.currentTimeMillis()) }
    // Historical gold/forex must not force a full chart-screen recomposition
    // every second when no live quote is subscribed.
    LaunchedEffect(uiState.selectedSymbol) {
        if (uiState.selectedSymbol in setOf("BTCUSDT", "ETHUSDT")) {
            while (true) {
                kotlinx.coroutines.delay(5_000L)
                quoteClock = System.currentTimeMillis()
            }
        }
    }
    val headerTick = uiState.latestTick
    val headerQuoteVerified = headerTick != null &&
        headerTick.symbol == uiState.selectedSymbol &&
        headerTick.source in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL") &&
        quoteClock - headerTick.timestamp in 0..15_000L

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(uiState.message) {
        uiState.message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearMessage()
        }
    }

    // Trade detail dialog when tapping a marker on chart
    uiState.selectedTradeForDetail?.let { trade ->
        TradeDetailDialog(trade = trade, onDismiss = { viewModel.selectTradeForDetail(null) })
    }

    if (showHistoricalSourceDialog) {
        AlertDialog(
            onDismissRequest = { showHistoricalSourceDialog = false },
            title = { Text("مصدر شموع الذهب والفوركس") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Twelve Data — بيانات تاريخية حقيقية بمفتاح API خاص بك. ليست أسعارًا مباشرة للتنفيذ.",
                        fontSize = 12.sp, color = TradingTextSecondary)
                    OutlinedTextField(
                        value = historicalApiKeyInput,
                        onValueChange = { historicalApiKeyInput = it },
                        label = { Text("Twelve Data API Key") },
                        singleLine = true,
                        visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth().testTag("chart_historical_provider_key")
                    )
                    Text("المفتاح يبقى في الذاكرة ولا يُحفظ في ملفات التطبيق.",
                        fontSize = 11.sp, color = TradingTextSecondary)
                }
            },
            confirmButton = {
                TextButton(
                    enabled = historicalApiKeyInput.isNotBlank(),
                    onClick = {
                        viewModel.configureHistoricalProviderKey(historicalApiKeyInput)
                        historicalApiKeyInput = ""
                        showHistoricalSourceDialog = false
                    }
                ) { Text("تفعيل وتحميل") }
            },
            dismissButton = { TextButton(onClick = { showHistoricalSourceDialog = false }) { Text("إلغاء") } }
        )
    }

    if (showIndicatorsDialog) {
        ChartIndicatorsDialog(
            currentSettings = uiState.indicatorSettings,
            onSaveSettings = { viewModel.updateIndicatorSettings(it) },
            onDismiss = { showIndicatorsDialog = false }
        )
    }

    Scaffold(
        modifier = modifier.testTag("chart_screen"),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .clickable { showSymbolSheet = true }
                            .testTag("symbol_selector_btn")
                    ) {
                        Text(
                            text = if (uiState.selectedSymbol.endsWith("USDT")) "${uiState.selectedSymbol.removeSuffix("USDT")} / USDT" else uiState.selectedSymbol,
                            style = TextStyle(textDirection = TextDirection.Ltr),
                            maxLines = 1,
                            fontWeight = FontWeight.ExtraBold,
                            fontSize = 16.sp,
                            color = TradingTextPrimary
                        )
                        Icon(Icons.Default.ArrowDropDown, contentDescription = null, tint = TradingTextSecondary)
                        Spacer(modifier = Modifier.width(4.dp))
                        if (headerQuoteVerified) {
                            DataSourceBadge(sourceType = uiState.dataSourceType)
                        } else {
                            Text(
                                text = when {
                                    uiState.isLoading -> "LOADING"
                                    uiState.candles.isNotEmpty() -> "HISTORY"
                                    uiState.candleLoadError != null -> "DATA ERROR"
                                    else -> "NO DATA"
                                },
                                fontSize = 10.sp, color = TradingTextSecondary,
                                modifier = Modifier.testTag("chart_source_mode")
                            )
                        }
                    }
                },
                actions = {
                    IconButton(
                        onClick = { immersiveChart = !immersiveChart },
                        modifier = Modifier.testTag("chart_immersive_toggle")
                    ) {
                        Icon(
                            if (immersiveChart) Icons.Default.FullscreenExit else Icons.Default.Fullscreen,
                            contentDescription = if (immersiveChart) "عرض التفاصيل" else "تكبير الشارت",
                            tint = TradingAccentLight
                        )
                    }
                    if (uiState.selectedSymbol in setOf("BTCUSDT", "ETHUSDT", "XAUUSD", "XAGUSD", "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD", "EURJPY", "GBPJPY", "EURGBP")) {
                        IconButton(
                            onClick = { viewModel.retryCandleLoad() },
                            modifier = Modifier.testTag("chart_header_refresh_btn")
                        ) {
                            Icon(
                                Icons.Default.Refresh,
                                contentDescription = "تحديث بيانات الشارت",
                                tint = TradingTextSecondary
                            )
                        }
                    }
                    // Replay shortcut
                    IconButton(
                        onClick = {
                            if (isEmbeddedReplay) {
                                replayViewModel.pause()
                                isEmbeddedReplay = false
                            } else {
                                replayViewModel.loadReplayData(uiState.selectedSymbol, uiState.selectedTimeframe)
                                isEmbeddedReplay = true
                            }
                        },
                        modifier = Modifier.testTag("chart_to_replay_btn")
                    ) {
                        Icon(Icons.Default.PlayCircle, contentDescription = if (isEmbeddedReplay) "إنهاء الإعادة" else "إعادة العرض داخل الشارت", tint = TradingAccentLight)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = TradingBackground)
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Distinguish a verified live quote from delayed or unsupported data.
            if (!immersiveChart && !headerQuoteVerified && !isEmbeddedReplay) {
                Text(
                    text = if (uiState.selectedSymbol in setOf("BTCUSDT", "ETHUSDT")) {
                        "السعر المباشر غير مؤكد حاليًا — لا تعتمد عليه لتنفيذ صفقة"
                    } else {
                        "لا يوجد مصدر أسعار مباشر موثوق لهذا الرمز"
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(TradingElevated)
                        .padding(horizontal = 12.dp, vertical = 6.dp)
                        .testTag("chart_quote_freshness_warning"),
                    color = TradingTextSecondary,
                    fontSize = 11.sp,
                    textAlign = TextAlign.Center
                )
            }

            if (isEmbeddedReplay) {
                Row(
                    modifier = Modifier.fillMaxWidth().background(TradingCard)
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                        .testTag("chart_embedded_replay_controls"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("REPLAY", color = TradingGold, fontWeight = FontWeight.Bold, fontSize = 11.sp)
                    IconButton(onClick = { replayViewModel.stepBackward() }, enabled = !replayState.isLoading) {
                        Icon(Icons.Default.SkipPrevious, contentDescription = "شمعة سابقة", tint = TradingTextPrimary)
                    }
                    IconButton(onClick = { if (replayState.isPlaying) replayViewModel.pause() else replayViewModel.play() },
                        enabled = !replayState.isLoading && replayState.totalCandles > 0) {
                        Icon(if (replayState.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = if (replayState.isPlaying) "إيقاف مؤقت" else "تشغيل الإعادة",
                            tint = TradingAccentLight)
                    }
                    IconButton(onClick = { replayViewModel.stepForward() }, enabled = !replayState.isLoading) {
                        Icon(Icons.Default.SkipNext, contentDescription = "شمعة تالية", tint = TradingTextPrimary)
                    }
                    Text("${(replayState.currentIndex + 1).coerceAtMost(replayState.totalCandles)}/${replayState.totalCandles}",
                        color = TradingTextSecondary, fontSize = 11.sp)
                    TextButton(onClick = { replayViewModel.pause(); isEmbeddedReplay = false }) {
                        Text("إنهاء", color = TradingNegative)
                    }
                }
                // Jump through real historical candles without leaving the chart.
                // The replay engine evaluates each skipped bar sequentially.
                Row(
                    modifier = Modifier.fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 8.dp, vertical = 2.dp)
                        .testTag("chart_replay_batch_steps"),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("تقدم", color = TradingTextSecondary, fontSize = 11.sp)
                    listOf(5, 10, 25, 50, 100).forEach { count ->
                        OutlinedButton(
                            onClick = { replayViewModel.advanceBars(count) },
                            enabled = !replayState.isLoading && replayState.totalCandles > 0 &&
                                replayState.currentIndex < replayState.totalCandles - 1,
                            modifier = Modifier.height(32.dp).testTag("chart_replay_advance_$count"),
                            contentPadding = PaddingValues(horizontal = 9.dp, vertical = 0.dp)
                        ) { Text("+$count", fontSize = 11.sp) }
                    }
                }
                TextButton(onClick = { showReplayDetails = !showReplayDetails }, modifier = Modifier.testTag("chart_replay_expand_btn")) {
                    Text(if (showReplayDetails) "إخفاء تفاصيل الإعادة ▲" else "أوامر وسرعة الإعادة ▼", fontSize = 11.sp)
                }
                if (showReplayDetails) {
                if (replayState.isBatchAdvancing && replayState.batchRequestedBars > 0) {
                    val progress = replayState.batchCompletedBars.toFloat() /
                        replayState.batchRequestedBars.toFloat()
                    Column(
                        modifier = Modifier.fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 4.dp)
                            .testTag("chart_replay_batch_progress")
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("معالجة الشموع والصفقات", fontSize = 11.sp, color = TradingTextSecondary)
                            Text(
                                "${replayState.batchCompletedBars}/${replayState.batchRequestedBars}",
                                fontSize = 11.sp, color = TradingGold
                            )
                        }
                        LinearProgressIndicator(
                            progress = { progress.coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth().height(3.dp)
                        )
                        TextButton(onClick = { replayViewModel.pause() }) {
                            Text("إيقاف التقدم", fontSize = 11.sp)
                        }
                    }
                }
                // Historical paper orders are isolated from the live-paper account.
                Row(
                    modifier = Modifier.fillMaxWidth().background(TradingCard)
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                        .testTag("chart_replay_trading_bar"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    val canTradeReplay = !replayState.isLoading &&
                        replayState.currentCandle != null && replayState.latestTick != null
                    Button(
                        onClick = { replayViewModel.executeOrder(OrderSide.SELL, 0.01) },
                        enabled = canTradeReplay,
                        colors = ButtonDefaults.buttonColors(containerColor = TradingNegative),
                        modifier = Modifier.weight(1f).testTag("chart_replay_sell")
                    ) { Text("بيع 0.01", fontSize = 12.sp) }
                    Button(
                        onClick = { replayViewModel.executeOrder(OrderSide.BUY, 0.01) },
                        enabled = canTradeReplay,
                        colors = ButtonDefaults.buttonColors(containerColor = TradingPositive),
                        modifier = Modifier.weight(1f).testTag("chart_replay_buy")
                    ) { Text("شراء 0.01", fontSize = 12.sp) }
                    Text(
                        "رصيد: ${String.format(Locale.US, "%.2f", replayState.currentBalance)}",
                        color = TradingTextSecondary, fontSize = 10.sp
                    )
                }
                Text(
                    "حقوق الحساب: ${String.format(Locale.US, "%.2f", replayState.currentEquity)} · " +
                        "العائم: ${String.format(Locale.US, "%.2f", replayState.currentEquity - replayState.currentBalance)}",
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp)
                        .testTag("chart_replay_equity"),
                    color = TradingTextSecondary,
                    fontSize = 11.sp
                )
                Row(
                    modifier = Modifier.fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .testTag("chart_replay_risk_summary"),
                    horizontalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Text("مراكز: ${replayState.openPositions.size}",
                        fontSize = 11.sp, color = TradingTextSecondary)
                    Text("أوامر معلقة: ${replayState.pendingOrders.size}",
                        fontSize = 11.sp, color = TradingTextSecondary)
                    Text("صفقات مغلقة: ${replayState.closedTrades.size}",
                        fontSize = 11.sp, color = TradingTextSecondary)
                    Text(
                        "تراجع: ${String.format(Locale.US, "%.1f", replayState.maxObservedDrawdownPercent)}%",
                        fontSize = 11.sp,
                        color = if (replayState.maxObservedDrawdownPercent > 10.0) TradingNegative else TradingGold
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(horizontal = 8.dp, vertical = 2.dp)
                        .testTag("chart_replay_speed"),
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("السرعة", color = TradingTextSecondary, fontSize = 11.sp)
                    listOf(0.5f, 1f, 2f, 5f, 10f, 25f, 50f, 100f).forEach { speed ->
                        val selected = replayState.speed == speed
                        Text(
                            text = "${speed}x",
                            modifier = Modifier
                                .clip(RoundedCornerShape(5.dp))
                                .background(if (selected) TradingAccent else TradingElevated)
                                .clickable { replayViewModel.setSpeed(speed) }
                                .padding(horizontal = 7.dp, vertical = 5.dp)
                                .testTag("chart_replay_speed_${speed}"),
                            color = if (selected) Color.White else TradingTextSecondary,
                            fontSize = 11.sp
                        )
                    }
                }
                if (replayState.openPositions.isNotEmpty()) {
                    Column(
                        modifier = Modifier.fillMaxWidth().background(TradingCard)
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                            .testTag("chart_replay_open_positions"),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text("الصفقات المفتوحة في المحاكاة", color = TradingTextSecondary, fontSize = 11.sp)
                        replayState.openPositions.forEach { position ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Text(
                                    "#${position.id} ${position.side.name} · ${position.volume}",
                                    color = TradingTextPrimary,
                                    fontSize = 11.sp,
                                    modifier = Modifier.weight(1f)
                                )
                                TextButton(
                                    onClick = { replayViewModel.setBreakEven(position.id) },
                                    enabled = !replayState.isLoading && replayState.latestTick != null,
                                    modifier = Modifier.testTag("chart_replay_breakeven_${position.id}")
                                ) { Text("تعادل", fontSize = 11.sp) }
                                TextButton(
                                    onClick = { replayViewModel.closePosition(position.id) },
                                    enabled = !replayState.isLoading && replayState.latestTick != null,
                                    modifier = Modifier.testTag("chart_replay_close_${position.id}")
                                ) { Text("إغلاق", color = TradingNegative, fontSize = 11.sp) }
                            }
                        }
                    }
                }
                if (replayState.isLoading || replayState.totalCandles == 0) {
                    Text(if (replayState.isLoading) "جار تحميل بيانات الإعادة..." else "لا تتوفر شموع تاريخية للإعادة",
                        color = TradingTextSecondary, fontSize = 11.sp,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                }
            }
            }

            // Timeframe selection scrollable row (all 10 timeframes)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 2.dp)
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Timeframe.values().forEach { tf ->
                    val isSelected = uiState.selectedTimeframe == tf
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (isSelected) TradingAccent else TradingElevated)
                            .clickable { viewModel.selectTimeframe(tf) }
                            .padding(horizontal = 9.dp, vertical = 7.dp)
                            .testTag("tf_chip_${tf.code}")
                    ) {
                        Text(
                            text = tf.displayName,
                            fontSize = 12.sp,
                            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                            color = if (isSelected) Color.White else TradingTextSecondary
                        )
                    }
                }

            }

            // Tools remain accessible as floating buttons when chart is expanded.
            if (immersiveChart) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = { showIndicatorsDialog = true }, modifier = Modifier.size(36.dp).testTag("chart_immersive_indicators")) {
                        Icon(Icons.Default.Timeline, contentDescription = "المؤشرات", tint = TradingAccentLight)
                    }
                    IconButton(onClick = { showToolsMenu = true }, modifier = Modifier.size(36.dp).testTag("chart_immersive_draw")) {
                        Icon(Icons.Default.Draw, contentDescription = "الرسم", tint = TradingAccentLight)
                    }
                    IconButton(onClick = { viewModel.triggerResetView() }, modifier = Modifier.size(36.dp).testTag("chart_immersive_reset")) {
                        Icon(Icons.Default.CenterFocusWeak, contentDescription = "إعادة ضبط الشارت", tint = TradingAccentLight)
                    }
                    IconButton(onClick = { showChartExtras = !showChartExtras }, modifier = Modifier.size(36.dp).testTag("chart_immersive_settings")) {
                        Icon(Icons.Default.Tune, contentDescription = "إعدادات الرسم", tint = TradingTextSecondary)
                    }
                }
            }
            // Compact icon toolbar: keep the chart as the primary surface.
            if (!immersiveChart) Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 1.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                IconButton(onClick = { showIndicatorsDialog = true }, modifier = Modifier.testTag("chart_indicators_btn")) {
                    Icon(Icons.Default.Timeline, contentDescription = "المؤشرات", tint = TradingAccentLight)
                }
                IconButton(onClick = { showToolsMenu = true }, modifier = Modifier.testTag("drawing_tools_menu_btn")) {
                    Icon(Icons.Default.Draw, contentDescription = "أدوات الرسم", tint = TradingAccentLight)
                }
                IconButton(onClick = { viewModel.triggerResetView() }, modifier = Modifier.testTag("chart_reset_view_btn")) {
                    Icon(Icons.Default.CenterFocusWeak, contentDescription = "ضبط الشارت", tint = TradingAccentLight)
                }
                IconButton(onClick = { showChartExtras = !showChartExtras }, modifier = Modifier.testTag("chart_extras_btn")) {
                    Icon(Icons.Default.Tune, contentDescription = "إعدادات الشارت", tint = TradingTextSecondary)
                }
            }
            if (showChartExtras) {
                Row(
                    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(horizontal = 8.dp, vertical = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    ChartDisplayStyle.values().forEach { style ->
                        TextButton(onClick = { chartDisplayStyle = style }, modifier = Modifier.testTag("chart_style_${style.name}")) {
                            Text(style.label, color = if (chartDisplayStyle == style) TradingAccentLight else TradingTextSecondary)
                        }
                    }
                    TextButton(onClick = { viewModel.toggleVolume() }) {
                        Text("VOL", color = if (uiState.isVolumeVisible) TradingGold else TradingTextSecondary)
                    }
                }
            }

            // Drawing tools active banner if tool active
            if (uiState.activeDrawingTool != DrawingTool.NONE) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(TradingAccent.copy(alpha = 0.12f))
                        .padding(horizontal = 14.dp, vertical = 5.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "أداة نشطة: ${uiState.activeDrawingTool.displayNameAr} (اسحب على الشارت)",
                        fontSize = 11.sp,
                        color = TradingAccentLight,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = "إلغاء",
                        fontSize = 12.sp,
                        color = TradingNegative,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.clickable { viewModel.setDrawingTool(DrawingTool.NONE) }
                    )
                }
            }

            // Market data provenance: never present missing or stale quotes as live.
            val marketTick = uiState.latestTick
            val marketTickIsLive = marketTick != null &&
                marketTick.symbol == uiState.selectedSymbol &&
                marketTick.source in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL") &&
                quoteClock - marketTick.timestamp in 0..15_000L
            val verifiedBinancePair = uiState.selectedSymbol in setOf("BTCUSDT", "ETHUSDT")
            val marketStatus = when {
                !verifiedBinancePair -> "لا يوجد مصدر أسعار مباشر معتمد لهذا الرمز"
                !marketTickIsLive -> "بانتظار سعر حديث من Binance"
                marketTick?.source == "BINANCE_WEBSOCKET" -> "Binance · بث مباشر"
                else -> "Binance · تحديث عبر الإنترنت"
            }
            if (!immersiveChart && !isEmbeddedReplay) Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 3.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = marketStatus,
                    color = if (marketTickIsLive) TradingPositive else TradingGold,
                    fontSize = 11.sp,
                    modifier = Modifier.testTag("chart_market_source_status")
                )
                if (!marketTickIsLive) {
                    Text("السعر غير متاح", color = TradingTextSecondary, fontSize = 10.sp)
                }
            }

            if (!immersiveChart && !isEmbeddedReplay && verifiedBinancePair && !marketTickIsLive) {
                Text(
                    text = "تشخيص الاتصال: ${uiState.connectionDiagnostic}",
                    color = TradingTextSecondary,
                    fontSize = 10.sp,
                    maxLines = 3,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                        .testTag("chart_connection_diagnostic")
                )
            }

            // Professional Candlestick Chart
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                CandlestickChart(
                    candles = if (isEmbeddedReplay) replayState.visibleCandles else uiState.candles,
                    latestTick = if (isEmbeddedReplay) replayState.latestTick else uiState.latestTick,
                    openPositions = if (isEmbeddedReplay) replayState.openPositions else uiState.openPositions,
                    pendingOrders = if (isEmbeddedReplay) replayState.pendingOrders else uiState.pendingOrders,
                    historicalTrades = if (isEmbeddedReplay) replayState.closedTrades else uiState.historicalTrades,
                    activeDrawingTool = if (isEmbeddedReplay) DrawingTool.NONE else uiState.activeDrawingTool,
                    drawings = if (isEmbeddedReplay) emptyList() else uiState.drawings,
                    indicatorSettings = uiState.indicatorSettings,
                    smaValues = if (isEmbeddedReplay) emptyList() else uiState.smaValues,
                    emaValues = if (isEmbeddedReplay) emptyList() else uiState.emaValues,
                    bollingerValues = if (isEmbeddedReplay) emptyList() else uiState.bollingerValues,
                    vwapValues = if (isEmbeddedReplay) emptyList() else uiState.vwapValues,
                    rsiValues = if (isEmbeddedReplay) emptyList() else uiState.rsiValues,
                    macdValues = if (isEmbeddedReplay) emptyList() else uiState.macdValues,
                    atrValues = if (isEmbeddedReplay) emptyList() else uiState.atrValues,
                    isCrosshairActive = uiState.isCrosshairActive,
                    isVolumeVisible = uiState.isVolumeVisible,
                    resetViewTrigger = uiState.resetViewTrigger,
                    displayStyle = chartDisplayStyle,
                    onAddDrawing = { if (!isEmbeddedReplay) viewModel.addDrawing(it) },
                    onSelectTrade = { viewModel.selectTradeForDetail(it) }
                )

                // Compact provenance HUD: historical candles are not live executable quotes.
                val chartBars = if (isEmbeddedReplay) replayState.visibleCandles else uiState.candles
                if (chartBars.isNotEmpty()) {
                    val latestBar = chartBars.last()
                    val timestamp = remember(latestBar.openTime) {
                        java.time.format.DateTimeFormatter.ofPattern("MM-dd HH:mm")
                            .withZone(java.time.ZoneOffset.UTC)
                            .format(java.time.Instant.ofEpochMilli(latestBar.openTime))
                    }
                    Surface(
                        color = TradingBackground.copy(alpha = 0.90f),
                        shape = RoundedCornerShape(8.dp),
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(start = 8.dp, top = 8.dp)
                            .testTag("chart_history_provenance")
                    ) {
                        Column(modifier = Modifier.padding(horizontal = 9.dp, vertical = 5.dp)) {
                            Text(
                                text = if (isEmbeddedReplay) "REPLAY" else "HISTORICAL · ${chartBars.size} bars",
                                fontSize = 10.sp, color = TradingTextPrimary
                            )
                            Text(
                                text = "${latestBar.source} · ${timestamp} UTC",
                                fontSize = 9.sp, color = TradingTextSecondary,
                                maxLines = 1
                            )
                        }
                    }
                }

                // Distinguish a failed Binance request from an in-progress load.
                if (!isEmbeddedReplay && uiState.candles.isEmpty() && !uiState.isLoading && uiState.candleLoadError != null) {
                    Column(
                        modifier = Modifier
                            .align(Alignment.Center)
                            .padding(horizontal = 50.dp)
                            .background(TradingCard, RoundedCornerShape(12.dp))
                            .padding(16.dp)
                            .testTag("chart_load_error"),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            text = uiState.candleLoadError ?: "",
                            color = TradingTextSecondary,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center
                        )
                        Button(
                            onClick = { viewModel.retryCandleLoad() },
                            modifier = Modifier.testTag("chart_retry_load_btn"),
                            colors = ButtonDefaults.buttonColors(containerColor = TradingAccent)
                        ) {
                            Text("إعادة المحاولة")
                        }
                    }
                }

                // Compact TradingView-style tools on the chart itself.
                // Buttons select the existing functional drawing tools; no image overlay.
                Surface(
                    modifier = Modifier
                        .align(Alignment.CenterStart)
                        .padding(horizontal = 5.dp)
                        .testTag("chart_floating_drawing_toolbar"),
                    shape = RoundedCornerShape(8.dp),
                    color = TradingCard.copy(alpha = 0.96f),
                    border = androidx.compose.foundation.BorderStroke(1.dp, TradingBorder),
                    tonalElevation = 0.dp
                ) {
                    Column(
                        modifier = Modifier
                            .heightIn(max = 228.dp)
                            .verticalScroll(rememberScrollState())
                            .padding(vertical = 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        val tools = listOf(
                            Triple(DrawingTool.NONE, Icons.Default.PanTool, "تحريك الشارت"),
                            Triple(DrawingTool.TRENDLINE, Icons.Default.ShowChart, "خط اتجاه"),
                            Triple(DrawingTool.HORIZONTAL_LINE, Icons.Default.HorizontalRule, "خط أفقي"),
                            Triple(DrawingTool.VERTICAL_LINE, Icons.Default.MoreVert, "خط رأسي"),
                            Triple(DrawingTool.RECTANGLE, Icons.Default.CropSquare, "مستطيل"),
                            Triple(DrawingTool.FIBONACCI, Icons.Default.AutoGraph, "فيبوناتشي")
                        )
                        tools.forEach { (tool, icon, description) ->
                            val selected = uiState.activeDrawingTool == tool
                            IconButton(
                                onClick = { viewModel.setDrawingTool(tool) },
                                modifier = Modifier.size(34.dp).testTag("chart_toolbar_${tool.name}")
                            ) {
                                Icon(
                                    imageVector = icon,
                                    contentDescription = description,
                                    tint = if (selected) TradingAccent else TradingTextSecondary,
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                        }
                        HorizontalDivider(modifier = Modifier.width(30.dp), color = TradingBorder)
                        IconButton(
                            onClick = { viewModel.toggleCrosshair() },
                            modifier = Modifier.size(34.dp).testTag("chart_toolbar_crosshair")
                        ) {
                            Icon(
                                Icons.Default.FilterCenterFocus,
                                contentDescription = "مؤشر التقاطع",
                                tint = if (uiState.isCrosshairActive) TradingAccent else TradingTextSecondary
                            )
                        }
                        IconButton(
                            onClick = { showToolsMenu = true },
                            modifier = Modifier.size(34.dp).testTag("chart_toolbar_more")
                        ) {
                            Icon(Icons.Default.MoreHoriz, contentDescription = "المزيد من أدوات الرسم", tint = TradingTextSecondary)
                        }
                    }
                }
            }

            // No executable bid/ask exists for historical-only metals and forex.
            // Keep their chart unobstructed; show execution only for crypto.
            if (uiState.selectedSymbol in setOf("BTCUSDT", "ETHUSDT")) Surface(
                color = TradingCard,
                tonalElevation = 0.dp,
                border = androidx.compose.foundation.BorderStroke(1.dp, TradingBorder)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 5.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // SELL Button (Red)
                    val bidText = if (marketTickIsLive) marketTick?.let { String.format(Locale.US, "%.2f", it.bid) } ?: "--" else "--"
                    Button(
                        onClick = { viewModel.quickOrder(OrderSide.SELL, 0.01) },
                        enabled = marketTickIsLive,
                        modifier = Modifier
                            .weight(1f)
                            .height(42.dp)
                            .testTag("chart_quick_sell_btn"),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingNegative)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("بيع", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                            Text(bidText, style = TextStyle(textDirection = TextDirection.Ltr, textAlign = TextAlign.Center), maxLines = 1, fontSize = 12.sp)
                        }
                    }

                    // Spread / Info Chip
                    val spreadText = (if (marketTickIsLive) marketTick else null)?.let {
                        val sym = DefaultSymbols.getSymbol(uiState.selectedSymbol)
                        String.format(Locale.US, "%.1f", it.spread / sym.pipSize)
                    } ?: "--"
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(text = "السبريد", fontSize = 10.sp, color = TradingTextSecondary)
                        Text(text = "$spreadText pips", style = TextStyle(textDirection = TextDirection.Ltr), maxLines = 1, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TradingTextPrimary)
                    }

                    // BUY Button (Green)
                    val askText = if (marketTickIsLive) marketTick?.let { String.format(Locale.US, "%.2f", it.ask) } ?: "--" else "--"
                    Button(
                        onClick = { viewModel.quickOrder(OrderSide.BUY, 0.01) },
                        enabled = marketTickIsLive,
                        modifier = Modifier
                            .weight(1f)
                            .height(46.dp)
                            .testTag("chart_quick_buy_btn"),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingPositive)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("شراء", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                            Text(askText, style = TextStyle(textDirection = TextDirection.Ltr, textAlign = TextAlign.Center), maxLines = 1, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }

    // Symbol Picker Bottom Sheet
    if (showSymbolSheet) {
        ModalBottomSheet(
            onDismissRequest = { showSymbolSheet = false },
            containerColor = TradingCard
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
            ) {
                Text(
                    text = "اختر أداة التداول",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(12.dp))
                DefaultSymbols.SYMBOLS.forEach { sym ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                viewModel.selectSymbol(sym.symbol)
                                showSymbolSheet = false
                            }
                            .padding(vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(text = sym.symbol, style = TextStyle(textDirection = TextDirection.Ltr), maxLines = 1, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                            Text(text = sym.name, fontSize = 12.sp, color = TradingTextSecondary)
                        }
                        Text(text = sym.category, fontSize = 11.sp, color = TradingAccentLight)
                    }
                    HorizontalDivider(color = TradingBorder)
                }
            }
        }
    }

    // Drawing Tools Menu Dialog
    if (showToolsMenu) {
        AlertDialog(
            onDismissRequest = { showToolsMenu = false },
            title = { Text("أدوات التحليل والرسم الفني", fontWeight = FontWeight.Bold) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    val tools = listOf(
                        DrawingTool.HORIZONTAL_LINE to "خط أفقي (دعم ومقاومة)",
                        DrawingTool.VERTICAL_LINE to "خط رأسي (توقيت)",
                        DrawingTool.TRENDLINE to "خط اتجاه (Trendline)",
                        DrawingTool.RECTANGLE to "مستطيل منطقة (Supply / Demand)",
                        DrawingTool.FIBONACCI to "مستويات فيبوناتشي (Fibonacci)",
                        DrawingTool.MEASUREMENT to "أداة القياس والمدى (Ruler)"
                    )
                    tools.forEach { (tool, label) ->
                        TextButton(
                            onClick = {
                                viewModel.setDrawingTool(tool)
                                showToolsMenu = false
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(label, modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Start)
                        }
                    }
                    HorizontalDivider(color = TradingBorder)
                    TextButton(
                        onClick = {
                            viewModel.clearDrawings()
                            showToolsMenu = false
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.DeleteOutline, contentDescription = null, tint = TradingNegative)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("مسح جميع الرسومات من الشارت", color = TradingNegative)
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showToolsMenu = false }) { Text("إغلاق") }
            }
        )
    }
}
