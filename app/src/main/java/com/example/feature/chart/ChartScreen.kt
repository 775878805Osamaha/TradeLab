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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
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
    onImmersiveChanged: (Boolean) -> Unit = {},
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
    LaunchedEffect(immersiveChart) { onImmersiveChanged(immersiveChart) }
    var drawingToolbarExpanded by remember { mutableStateOf(false) }
    var replaySpeedMenuExpanded by remember { mutableStateOf(false) }
    var pendingOrderSide by remember { mutableStateOf<OrderSide?>(null) }
    var orderVolumeInput by remember { mutableStateOf("0.01") }
    var orderSlInput by remember { mutableStateOf("") }
    var orderTpInput by remember { mutableStateOf("") }
    var showReplayDatePicker by remember { mutableStateOf(false) }
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

    LaunchedEffect(pendingOrderSide) {
        if (pendingOrderSide != null) {
            orderSlInput = ""
            orderTpInput = ""
        }
    }

    if (pendingOrderSide != null) {
        val side = pendingOrderSide!!
        val volume = orderVolumeInput.toDoubleOrNull()
        val validVolume = volume != null && volume.isFinite() && volume > 0.0
        val entryTick = if (isEmbeddedReplay) replayState.latestTick else headerTick
        val entryPrice = entryTick?.let { if (side == OrderSide.BUY) it.ask else it.bid }
        val sl = orderSlInput.trim().takeIf { it.isNotEmpty() }?.toDoubleOrNull()
        val tp = orderTpInput.trim().takeIf { it.isNotEmpty() }?.toDoubleOrNull()
        val validSl = orderSlInput.isBlank() || (sl != null && sl.isFinite() && sl > 0.0 &&
            entryPrice != null && (if (side == OrderSide.BUY) sl < entryPrice else sl > entryPrice))
        val validTp = orderTpInput.isBlank() || (tp != null && tp.isFinite() && tp > 0.0 &&
            entryPrice != null && (if (side == OrderSide.BUY) tp > entryPrice else tp < entryPrice))
        val validOrder = validVolume && validSl && validTp &&
            entryTick?.symbol == (if (isEmbeddedReplay) replayState.symbol else uiState.selectedSymbol) &&
            entryPrice != null &&
            entryPrice.isFinite() && entryPrice > 0.0 && entryTick != null &&
            entryTick.bid.isFinite() && entryTick.ask.isFinite() &&
            entryTick.bid > 0.0 && entryTick.ask >= entryTick.bid
        AlertDialog(
            onDismissRequest = { pendingOrderSide = null },
            title = { Text(if (side == OrderSide.BUY) "تأكيد أمر شراء" else "تأكيد أمر بيع") },
            text = {
                Column(modifier = Modifier.verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("حساب تجريبي: راجع الحجم قبل التنفيذ.")
                    OutlinedTextField(
                        value = orderVolumeInput,
                        onValueChange = { orderVolumeInput = it },
                        label = { Text("حجم الصفقة (لوت)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().testTag("chart_order_volume")
                    )
                    Text("سعر الدخول: ${entryPrice?.let { String.format(Locale.US, "%.5f", it) } ?: "--"}")
                    OutlinedTextField(
                        value = orderSlInput, onValueChange = { orderSlInput = it },
                        label = { Text("وقف الخسارة (اختياري)") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        isError = !validSl, modifier = Modifier.fillMaxWidth().testTag("chart_order_sl")
                    )
                    OutlinedTextField(
                        value = orderTpInput, onValueChange = { orderTpInput = it },
                        label = { Text("جني الربح (اختياري)") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        isError = !validTp, modifier = Modifier.fillMaxWidth().testTag("chart_order_tp")
                    )
                    if (sl != null && entryPrice != null && validSl && validVolume) {
                        Text("المخاطرة السعرية: ${String.format(Locale.US, "%.5f", kotlin.math.abs(entryPrice - sl))} لكل وحدة")
                        val ratio = if (tp != null && validTp) kotlin.math.abs(tp - entryPrice) / kotlin.math.abs(entryPrice - sl) else null
                        if (ratio != null && ratio.isFinite()) Text("العائد إلى المخاطرة: 1:${String.format(Locale.US, "%.2f", ratio)}")
                        Text("المخاطرة النقدية تتطلب قيمة العقد الفعلية", fontSize = 11.sp, color = TradingTextSecondary)
                    }
                    if (!validSl || !validTp) Text("تحقق من اتجاه ومستوى وقف الخسارة وجني الربح", color = TradingNegative)
                }
            },
            confirmButton = {
                TextButton(
                    enabled = validOrder &&
                        (if (isEmbeddedReplay) !replayState.isLoading &&
                            replayState.currentCandle != null && replayState.latestTick != null
                        else headerQuoteVerified),
                    onClick = {
                        val confirmedVolume = orderVolumeInput.toDoubleOrNull()
                        if (confirmedVolume != null && confirmedVolume.isFinite() && confirmedVolume > 0.0 && validOrder) {
                            if (isEmbeddedReplay) replayViewModel.executeOrder(side, confirmedVolume, sl, tp)
                            else viewModel.quickOrder(side, confirmedVolume, sl, tp)
                            pendingOrderSide = null
                        }
                    },
                    modifier = Modifier.testTag("chart_order_confirm")
                ) { Text("تأكيد التنفيذ") }
            },
            dismissButton = { TextButton(onClick = { pendingOrderSide = null }) { Text("إلغاء") } }
        )
    }

    if (showReplayDatePicker) {
        val datePickerState = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { showReplayDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        datePickerState.selectedDateMillis?.let { selected ->
                            replayViewModel.jumpToTimestamp(selected)
                        }
                        showReplayDatePicker = false
                    },
                    enabled = datePickerState.selectedDateMillis != null
                ) { Text("انتقال") }
            },
            dismissButton = {
                TextButton(onClick = { showReplayDatePicker = false }) { Text("إلغاء") }
            }
        ) { DatePicker(state = datePickerState) }
    }

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
                modifier = Modifier.height(if (immersiveChart) 44.dp else 64.dp),
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
                        if (!immersiveChart) {
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
                    if (!immersiveChart) {
                    IconButton(
                        onClick = { viewModel.toggleVolume() },
                        modifier = Modifier.testTag("chart_toggle_volume_header")
                    ) {
                        Icon(
                            Icons.Default.BarChart,
                            contentDescription = if (uiState.isVolumeVisible) "إخفاء أحجام التداول" else "إظهار أحجام التداول",
                            tint = if (uiState.isVolumeVisible) TradingAccentLight else TradingTextSecondary
                        )
                    }
                    IconButton(
                        onClick = { viewModel.triggerResetView() },
                        modifier = Modifier.testTag("chart_reset_view_header")
                    ) {
                        Icon(Icons.Default.CenterFocusStrong, contentDescription = "إعادة ضبط الشارت", tint = TradingTextSecondary)
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
                    }
                    // Replay shortcut remains available from the chart header.
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
            if (isEmbeddedReplay) {
                // Replay detail controls remain available without occupying
                // vertical chart space in the default reference layout.
                if (!immersiveChart || showReplayDetails) {
                    TextButton(onClick = { showReplayDetails = !showReplayDetails }, modifier = Modifier.testTag("chart_replay_expand_btn")) {
                        Text(if (showReplayDetails) "إخفاء تفاصيل الإعادة ▲" else "أوامر وسرعة الإعادة ▼", fontSize = 11.sp)
                    }
                }
                if (showReplayDetails) {
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
                // Choose historical depth in place; reloads the same real provider
                // and resets the simulated account to prevent mixed sessions.
                Row(
                    modifier = Modifier.fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                        .testTag("chart_replay_history_depth"),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("الشموع", color = TradingTextSecondary, fontSize = 11.sp)
                    listOf(100, 300, 500, 900).forEach { bars ->
                        val selected = replayState.requestedHistoryBars == bars
                        OutlinedButton(
                            onClick = {
                                replayViewModel.loadReplayData(
                                    uiState.selectedSymbol, uiState.selectedTimeframe,
                                    historyBars = bars
                                )
                            },
                            enabled = !replayState.isLoading && !replayState.isBatchAdvancing,
                            modifier = Modifier.height(32.dp).testTag("chart_replay_history_$bars"),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp)
                        ) {
                            Text(
                                "$bars",
                                fontSize = 11.sp,
                                color = if (selected) TradingAccentLight else TradingTextSecondary
                            )
                        }
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                        .testTag("chart_replay_history_offset"),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("قبل", color = TradingTextSecondary, fontSize = 11.sp)
                    listOf(0, 100, 300, 600, 1200).forEach { offset ->
                        OutlinedButton(
                            onClick = {
                                replayViewModel.loadReplayData(
                                    uiState.selectedSymbol,
                                    uiState.selectedTimeframe,
                                    endOffsetBars = offset
                                )
                            },
                            enabled = !replayState.isLoading && !replayState.isBatchAdvancing,
                            modifier = Modifier.height(32.dp).testTag("chart_replay_offset_$offset"),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp)
                        ) {
                            Text(
                                if (offset == 0) "الأحدث" else "-$offset",
                                fontSize = 11.sp,
                                color = if (replayState.historyEndOffsetBars == offset)
                                    TradingAccentLight else TradingTextSecondary
                            )
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
                        onClick = { pendingOrderSide = OrderSide.SELL },
                        enabled = canTradeReplay,
                        colors = ButtonDefaults.buttonColors(containerColor = TradingNegative),
                        modifier = Modifier.weight(1f).testTag("chart_replay_sell")
                    ) { Text("بيع 0.01", fontSize = 12.sp) }
                    Button(
                        onClick = { pendingOrderSide = OrderSide.BUY },
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
                    listOf(1f, 2f, 5f).forEach { speed ->
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
                replayState.message?.takeIf { it.isNotBlank() }?.let { replayMessage ->
                    Text(
                        replayMessage,
                        color = TradingGold,
                        fontSize = 11.sp,
                        modifier = Modifier.fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 4.dp)
                            .testTag("chart_replay_status_message")
                    )
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
                modifier = Modifier.fillMaxWidth().height(if (immersiveChart) 36.dp else 48.dp)
                    .background(TradingBackground)
                    .testTag("chart_timeframe_strip"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                listOf(Timeframe.M1, Timeframe.M5, Timeframe.M15, Timeframe.H1, Timeframe.H4, Timeframe.D1).forEach { tf ->
                    val selected = uiState.selectedTimeframe == tf
                    Column(
                        modifier = Modifier.weight(1f).fillMaxHeight()
                            .clickable { viewModel.selectTimeframe(tf) }
                            .testTag("tf_chip_${tf.code}"),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Bottom
                    ) {
                        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                            Text(tf.displayName, fontSize = 13.sp,
                                color = if (selected) TradingAccentLight else TradingTextSecondary,
                                fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal)
                        }
                        Box(Modifier.width(29.dp).height(3.dp)
                            .background(if (selected) TradingAccent else Color.Transparent))
                    }
                }
                IconButton(onClick = { showIndicatorsDialog = true }, modifier = Modifier.size(38.dp)) {
                    Icon(Icons.Default.Functions, contentDescription = "المؤشرات", tint = TradingTextPrimary)
                }
                if (!immersiveChart) {
                    IconButton(onClick = { showChartExtras = !showChartExtras }, modifier = Modifier.size(38.dp)) {
                        Icon(Icons.Default.MoreHoriz, contentDescription = "المزيد", tint = TradingTextPrimary)
                    }
                }
            }

            val marketTick = uiState.latestTick
            val marketTickIsLive = marketTick != null &&
                marketTick.symbol == uiState.selectedSymbol &&
                marketTick.source in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL") &&
                quoteClock - marketTick.timestamp in 0..15_000L
            val verifiedBinancePair = uiState.selectedSymbol in setOf("BTCUSDT", "ETHUSDT")
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

            // Verified historical OHLC depth: bounded presets avoid oversized requests.
            if (!immersiveChart && !isEmbeddedReplay) {
                Row(
                    modifier = Modifier.fillMaxWidth()
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                        .testTag("chart_history_controls"),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("الشموع", fontSize = 10.sp, color = TradingTextSecondary)
                    listOf(100, 250, 500, 750).forEach { bars ->
                        val selected = uiState.chartHistoryBars == bars
                        OutlinedButton(
                            onClick = { viewModel.setChartHistoryBars(bars) },
                            enabled = !uiState.isLoading,
                            modifier = Modifier.height(30.dp).testTag("chart_history_depth_$bars"),
                            contentPadding = PaddingValues(horizontal = 7.dp, vertical = 0.dp),
                            colors = ButtonDefaults.outlinedButtonColors(
                                contentColor = if (selected) TradingAccentLight else TradingTextSecondary
                            )
                        ) {
                            Text("$bars", fontSize = 10.sp)
                        }
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    IconButton(
                        onClick = { viewModel.retryChartHistory() },
                        enabled = !uiState.isLoading,
                        modifier = Modifier.size(30.dp).testTag("chart_history_retry")
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = "إعادة تحميل الشموع",
                            tint = TradingAccentLight, modifier = Modifier.size(17.dp))
                    }
                }
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
                if (!immersiveChart && chartBars.isNotEmpty()) {
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
                            if (!isEmbeddedReplay) {
                                val oldest = chartBars.first()
                                val firstTime = remember(oldest.openTime) {
                                    java.time.format.DateTimeFormatter.ofPattern("MM-dd HH:mm")
                                        .withZone(java.time.ZoneOffset.UTC)
                                        .format(java.time.Instant.ofEpochMilli(oldest.openTime))
                                }
                                Text(
                                    text = "$firstTime → $timestamp UTC · ${chartBars.size}/${uiState.chartHistoryBars}",
                                    fontSize = 9.sp,
                                    color = TradingTextSecondary,
                                    modifier = Modifier.testTag("chart_history_range"),
                                    maxLines = 1
                                )
                                val firstPrice = oldest.open
                                val lastPrice = latestBar.close
                                if (firstPrice > 0.0 && firstPrice.isFinite() && lastPrice.isFinite()) {
                                    val changePercent = (lastPrice - firstPrice) / firstPrice * 100.0
                                    val sign = if (changePercent >= 0.0) "+" else ""
                                    Text(
                                        text = "Δ $sign${"%.2f".format(java.util.Locale.US, changePercent)}% · H ${"%.5f".format(java.util.Locale.US, chartBars.maxOf { it.high })} · L ${"%.5f".format(java.util.Locale.US, chartBars.minOf { it.low })}",
                                        fontSize = 9.sp,
                                        color = if (changePercent >= 0.0) TradingPositive else TradingGold,
                                        maxLines = 1,
                                        modifier = Modifier.testTag("chart_history_summary")
                                    )
                                }
                            }
                        }
                    }
                }

                // Never render a fabricated placeholder candle when history is unavailable.
                if ((if (isEmbeddedReplay) replayState.visibleCandles.isEmpty() && !replayState.isLoading
                    else uiState.candles.isEmpty() && !uiState.isLoading)) {
                    Text(
                        "لا توجد بيانات",
                        modifier = Modifier.align(Alignment.Center).testTag("chart_no_data"),
                        color = TradingTextSecondary,
                        fontSize = 15.sp
                    )
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
                        .align(if (immersiveChart) Alignment.TopStart else Alignment.CenterStart)
                        .padding(horizontal = 5.dp, vertical = if (immersiveChart) 12.dp else 0.dp)
                        .testTag("chart_floating_drawing_toolbar"),
                    shape = RoundedCornerShape(8.dp),
                    color = TradingCard.copy(alpha = if (drawingToolbarExpanded) 0.96f else 0.72f),
                    border = if (drawingToolbarExpanded) androidx.compose.foundation.BorderStroke(1.dp, TradingBorder) else null,
                    tonalElevation = 0.dp
                ) {
                    Column(
                        modifier = Modifier
                            .heightIn(max = if (drawingToolbarExpanded) 228.dp else 92.dp)
                            .verticalScroll(rememberScrollState())
                            .padding(vertical = 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        IconButton(
                            onClick = { drawingToolbarExpanded = !drawingToolbarExpanded },
                            modifier = Modifier.size(40.dp).testTag("chart_toolbar_collapse")
                        ) {
                            Icon(
                                if (!drawingToolbarExpanded && uiState.activeDrawingTool != DrawingTool.NONE && !isEmbeddedReplay)
                                    Icons.Default.Edit else Icons.Default.MoreHoriz,
                                contentDescription = if (drawingToolbarExpanded) "إخفاء أدوات الرسم" else "إظهار أدوات الرسم",
                                tint = if (uiState.activeDrawingTool != DrawingTool.NONE) TradingAccent else TradingTextPrimary
                            )
                        }
                        // Keep pan/reset accessible without expanding the full tools palette.
                        if (!drawingToolbarExpanded && uiState.activeDrawingTool != DrawingTool.NONE && !isEmbeddedReplay) {
                            IconButton(
                                onClick = {
                                    viewModel.setDrawingTool(DrawingTool.NONE)
                                    drawingToolbarExpanded = false
                                },
                                modifier = Modifier.size(40.dp).testTag("chart_toolbar_quick_pan")
                            ) {
                                Icon(Icons.Default.PanTool, contentDescription = "تحريك الشارت",
                                    tint = if (uiState.activeDrawingTool == DrawingTool.NONE) TradingAccent else TradingTextSecondary,
                                    modifier = Modifier.size(18.dp))
                            }
                            IconButton(
                                onClick = { viewModel.triggerResetView() },
                                modifier = Modifier.size(40.dp).testTag("chart_toolbar_quick_reset")
                            ) {
                                Icon(Icons.Default.CenterFocusStrong, contentDescription = "إعادة الشارت إلى آخر شمعة",
                                    tint = TradingTextSecondary, modifier = Modifier.size(18.dp))
                            }
                        }
                        if (drawingToolbarExpanded) {
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
                                onClick = {
                                    viewModel.setDrawingTool(tool)
                                    drawingToolbarExpanded = false
                                },
                                modifier = Modifier.size(44.dp).testTag("chart_toolbar_${tool.name}")
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
                            modifier = Modifier.size(44.dp).testTag("chart_toolbar_crosshair")
                        ) {
                            Icon(
                                Icons.Default.FilterCenterFocus,
                                contentDescription = "مؤشر التقاطع",
                                tint = if (uiState.isCrosshairActive) TradingAccent else TradingTextSecondary
                            )
                        }
                        IconButton(
                            onClick = { uiState.drawings.lastOrNull()?.let { viewModel.deleteDrawing(it.id) } },
                            enabled = uiState.drawings.isNotEmpty(),
                            modifier = Modifier.size(44.dp).testTag("chart_toolbar_undo")
                        ) {
                            Icon(Icons.Default.Undo, contentDescription = "التراجع عن آخر رسم",
                                tint = TradingTextSecondary)
                        }
                        IconButton(
                            onClick = { showToolsMenu = true },
                            modifier = Modifier.size(44.dp).testTag("chart_toolbar_more")
                        ) {
                            Icon(Icons.Default.MoreHoriz, contentDescription = "المزيد من أدوات الرسم", tint = TradingTextSecondary)
                        }
                        }
                    }
                }
            }

            if (isEmbeddedReplay) {
                Row(
                    modifier = Modifier.fillMaxWidth().height(if (immersiveChart) 44.dp else 52.dp)
                        .background(TradingBackground)
                        .testTag("chart_embedded_replay_controls"),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = { showReplayDatePicker = true }, modifier = Modifier.testTag("chart_replay_date_picker")) {
                        Icon(Icons.Default.DateRange, contentDescription = "تاريخ الإعادة", tint = TradingTextPrimary)
                        Text(" ${replayState.currentIndex + 1}", fontSize = 11.sp, color = TradingTextPrimary)
                    }
                    IconButton(onClick = { replayViewModel.stepBackward() },
                        enabled = !replayState.isLoading && replayState.currentIndex > 0,
                        modifier = Modifier.testTag("chart_replay_step_back")) {
                        Icon(Icons.Default.SkipPrevious, contentDescription = "رجوع شمعة", tint = TradingTextPrimary)
                    }
                    IconButton(onClick = { if (replayState.isPlaying) replayViewModel.pause() else replayViewModel.play() },
                        enabled = !replayState.isLoading && replayState.totalCandles > 0,
                        modifier = Modifier.testTag("chart_replay_play_pause")) {
                        Icon(if (replayState.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = "تشغيل أو إيقاف", tint = TradingAccent)
                    }
                    IconButton(onClick = { replayViewModel.stepForward() },
                        enabled = !replayState.isLoading && replayState.currentIndex < replayState.totalCandles - 1,
                        modifier = Modifier.testTag("chart_replay_step_next")) {
                        Icon(Icons.Default.SkipNext, contentDescription = "تقدم شمعة", tint = TradingTextPrimary)
                    }
                    Box {
                        TextButton(onClick = { replaySpeedMenuExpanded = true }) {
                            Text("${replayState.speed}x", color = TradingTextPrimary)
                            Icon(Icons.Default.ArrowDropDown, contentDescription = "سرعة الإعادة", tint = TradingTextPrimary)
                        }
                        DropdownMenu(expanded = replaySpeedMenuExpanded,
                            onDismissRequest = { replaySpeedMenuExpanded = false }) {
                            listOf(0.5f, 1f, 2f, 5f, 10f, 25f, 50f, 100f).forEach { speed ->
                                DropdownMenuItem(text = { Text("${speed}x") },
                                    onClick = { replayViewModel.setSpeed(speed); replaySpeedMenuExpanded = false })
                            }
                        }
                    }
                    IconButton(onClick = { replayViewModel.pause(); isEmbeddedReplay = false },
                        modifier = Modifier.testTag("chart_replay_close")) {
                        Icon(Icons.Default.Close, contentDescription = "إغلاق الإعادة", tint = TradingTextPrimary)
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
                        onClick = { pendingOrderSide = OrderSide.SELL },
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
                        onClick = { pendingOrderSide = OrderSide.BUY },
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
