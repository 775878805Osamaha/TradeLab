package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.layout.onSizeChanged
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.AbsoluteAlignment
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
import androidx.compose.ui.window.Dialog
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
    embeddedReplayLaunchRequest: Int = 0,
    onImmersiveChanged: (Boolean) -> Unit = {},
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val replayState by replayViewModel.uiState.collectAsState()
    var isEmbeddedReplay by remember { mutableStateOf(false) }
    LaunchedEffect(embeddedReplayLaunchRequest) {
        if (embeddedReplayLaunchRequest > 0) {
            replayViewModel.loadReplayData(uiState.selectedSymbol, uiState.selectedTimeframe)
            isEmbeddedReplay = true
        }
    }
    var showSymbolSheet by remember { mutableStateOf(false) }
    var symbolSearchQuery by remember { mutableStateOf("") }
    var symbolCategoryFilter by remember { mutableStateOf("الكل") }
    // Save a list rather than a Set so Compose's default Bundle saver can restore it.
    var favoriteSymbolsList by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    val favoriteSymbols = favoriteSymbolsList.toSet()
    var favoritesOnly by remember { mutableStateOf(false) }
    var symbolSortFavoritesFirst by remember { mutableStateOf(true) }
    var recentSymbols by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    var recentOnly by remember { mutableStateOf(false) }
    LaunchedEffect(showSymbolSheet) {
        if (showSymbolSheet) {
            symbolSearchQuery = ""
            symbolCategoryFilter = "الكل"
            favoritesOnly = false
            recentOnly = false
        }
    }
    var showToolsMenu by remember { mutableStateOf(false) }
    var showReplayDetails by remember { mutableStateOf(false) }
    var showChartExtras by remember { mutableStateOf(false) }
    var showIndicatorsDialog by remember { mutableStateOf(false) }
    var chartDisplayStyle by remember { mutableStateOf(ChartDisplayStyle.CANDLES) }
    var immersiveChart by remember { mutableStateOf(true) }
    var pendingAnnotation by remember { mutableStateOf<com.example.feature.chart.model.ChartDrawing?>(null) }
    var annotationText by remember { mutableStateOf("") }
    var magnetEnabled by rememberSaveable { mutableStateOf(false) }
    var drawingToolbarExpanded by remember { mutableStateOf(false) }
    var drawingPaletteOffsetPx by rememberSaveable { mutableFloatStateOf(0f) }
    var drawingPaletteXOffsetPx by rememberSaveable { mutableFloatStateOf(0f) }
    var drawingPaletteCollapsed by rememberSaveable { mutableStateOf(false) }
    var chartPaletteContainerWidthPx by remember { mutableIntStateOf(0) }
    var drawingPaletteWidthPx by remember { mutableIntStateOf(0) }
    var chartPaletteContainerHeightPx by remember { mutableIntStateOf(0) }
    var drawingPaletteHeightPx by remember { mutableIntStateOf(0) }
    val paletteDensity = LocalDensity.current
    val chartPaletteTopInsetPx = with(paletteDensity) { (if (isEmbeddedReplay) 148.dp else 52.dp).toPx() }
    val chartPaletteMaxYOffsetPx = (chartPaletteContainerHeightPx - drawingPaletteHeightPx - chartPaletteTopInsetPx).coerceAtLeast(0f)
    val chartPaletteMaxXOffsetPx = (chartPaletteContainerWidthPx - drawingPaletteWidthPx - with(paletteDensity) { 80.dp.toPx() }).coerceAtLeast(0f)
    LaunchedEffect(chartPaletteContainerHeightPx, drawingPaletteHeightPx, chartPaletteContainerWidthPx, drawingPaletteWidthPx, isEmbeddedReplay) {
        if (chartPaletteContainerHeightPx > 0 && drawingPaletteHeightPx > 0) {
            // On small screens the full rail can exceed the available candle viewport.
            // Collapse it instead of letting tools cover the price axis or order area.
            // The collapse control remains available to expand it again manually.
            if (!drawingPaletteCollapsed &&
                drawingPaletteHeightPx > (chartPaletteContainerHeightPx - chartPaletteTopInsetPx)) {
                drawingPaletteCollapsed = true
            }
            drawingPaletteOffsetPx = drawingPaletteOffsetPx.coerceIn(0f, chartPaletteMaxYOffsetPx)
            drawingPaletteXOffsetPx = drawingPaletteXOffsetPx.coerceIn(0f, chartPaletteMaxXOffsetPx)
        }
    }
    LaunchedEffect(immersiveChart) { onImmersiveChanged(immersiveChart) }
    // Keep the floating palette compact when the displayed market context changes.
    LaunchedEffect(uiState.selectedSymbol, uiState.selectedTimeframe, isEmbeddedReplay) {
        drawingToolbarExpanded = false
        showToolsMenu = false
        showChartExtras = false
        showIndicatorsDialog = false
        showReplayDetails = false
    }
    var replaySpeedMenuExpanded by remember { mutableStateOf(false) }
    var floatingTimeframeMenuExpanded by remember { mutableStateOf(false) }
    var pendingOrderSide by remember { mutableStateOf<OrderSide?>(null) }
    var orderVolumeInput by remember { mutableStateOf("0.01") }
    var orderSlInput by remember { mutableStateOf("") }
    var riskEquityInput by remember { mutableStateOf("") }
    var riskPercentInput by remember { mutableStateOf("1") }
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
        val riskSymbol = if (isEmbeddedReplay) replayState.symbol else uiState.selectedSymbol
        val symbolSpec = com.example.core.market.DefaultSymbols.SYMBOLS.firstOrNull {
            it.symbol.equals(riskSymbol, ignoreCase = true) ||
                (riskSymbol.equals("BTCUSD", ignoreCase = true) && it.symbol == "BTCUSDT") ||
                (riskSymbol.equals("ETHUSD", ignoreCase = true) && it.symbol == "ETHUSDT")
        }
        val validLotStep = volume != null && symbolSpec != null &&
            volume >= symbolSpec.minLot && volume <= symbolSpec.maxLot &&
            kotlin.math.abs(volume / symbolSpec.lotStep -
                kotlin.math.round(volume / symbolSpec.lotStep)) <= 1e-6
        val riskEquity = riskEquityInput.trim().toDoubleOrNull()
        val riskPercent = riskPercentInput.trim().toDoubleOrNull()
        val riskBudgetValid = riskEquityInput.isBlank() ||
            (riskEquity != null && riskEquity.isFinite() && riskEquity > 0.0 &&
                riskPercent != null && riskPercent.isFinite() && riskPercent > 0.0 && riskPercent <= 100.0)
        val riskEstimate = if (sl != null && validSl && validTp &&
            entryPrice != null && volume != null && validVolume) {
            com.example.core.execution.TradeRiskCalculator.estimate(
                symbol = if (isEmbeddedReplay) replayState.symbol else uiState.selectedSymbol,
                side = side,
                entryPrice = entryPrice,
                stopLoss = sl,
                takeProfit = tp,
                volumeLots = volume,
                equityUsd = if (riskEquityInput.isBlank()) null else riskEquity,
                targetRiskPercent = if (riskEquityInput.isBlank()) null else riskPercent
            )
        } else null
        val withinRiskBudget = riskEquityInput.isBlank() ||
            (riskEstimate != null && riskPercent != null &&
                riskEstimate.riskPercentOfEquity != null &&
                riskEstimate.riskPercentOfEquity <= riskPercent + 1e-8)
        val validOrder = validVolume && validLotStep && validSl && validTp && riskBudgetValid &&
            (riskEquityInput.isBlank() || (sl != null && riskEstimate != null)) &&
            withinRiskBudget &&
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
                    if (validVolume && !validLotStep) {
                        Text("حجم العقد خارج حدود الرمز أو لا يطابق خطوة اللوت",
                            color = TradingNegative,
                            modifier = Modifier.testTag("chart_order_invalid_lot_step"))
                    }
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
                    OutlinedTextField(
                        value = riskEquityInput,
                        onValueChange = { riskEquityInput = it },
                        label = { Text("رأس المال بالدولار (اختياري لحساب المخاطرة)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                        isError = !riskBudgetValid,
                        modifier = Modifier.fillMaxWidth().testTag("chart_risk_equity")
                    )
                    if (riskEquityInput.isNotBlank()) {
                        OutlinedTextField(
                            value = riskPercentInput,
                            onValueChange = { riskPercentInput = it },
                            label = { Text("المخاطرة المستهدفة %") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            singleLine = true,
                            isError = !riskBudgetValid,
                            modifier = Modifier.fillMaxWidth().testTag("chart_risk_percent")
                        )
                    }
                    if (riskBudgetValid && !withinRiskBudget) {
                        Text("حجم العقد يتجاوز نسبة المخاطرة المحددة؛ خفّض اللوت قبل التأكيد",
                            color = TradingNegative, modifier = Modifier.testTag("chart_risk_budget_exceeded"))
                    }
                    if (!riskBudgetValid) {
                        Text("أدخل رأس مال موجبًا ونسبة مخاطرة بين 0 و100",
                            color = TradingNegative)
                    }
                    if (sl != null && entryPrice != null && validSl && validVolume) {
                        Text("المخاطرة السعرية: ${String.format(Locale.US, "%.5f", kotlin.math.abs(entryPrice - sl))} لكل وحدة")
                        val ratio = if (tp != null && validTp) kotlin.math.abs(tp - entryPrice) / kotlin.math.abs(entryPrice - sl) else null
                        if (ratio != null && ratio.isFinite()) Text("العائد إلى المخاطرة: 1:${String.format(Locale.US, "%.2f", ratio)}")
                        if (riskEstimate != null) {
                            Text("الخسارة المتوقعة: ${String.format(Locale.US, "%.2f", riskEstimate.riskUsd)} USD",
                                color = TradingNegative, modifier = Modifier.testTag("chart_order_risk_usd"))
                            riskEstimate.rewardUsd?.let { reward ->
                                Text("الربح المحتمل: ${String.format(Locale.US, "%.2f", reward)} USD",
                                    color = TradingPositive, modifier = Modifier.testTag("chart_order_reward_usd"))
                            }
                            if (riskEquityInput.isNotBlank()) {
                                riskEstimate.riskPercentOfEquity?.let { pct ->
                                    Text("المخاطرة من رأس المال: ${String.format(Locale.US, "%.2f", pct)}%",
                                        color = TradingTextSecondary,
                                        modifier = Modifier.testTag("chart_risk_equity_percent"))
                                }
                                riskEstimate.maximumLotsForRisk?.let { lots ->
                                    Text("الحجم المقترح للمخاطرة المحددة: ${String.format(Locale.US, "%.2f", lots)} لوت",
                                        color = TradingPositive,
                                        modifier = Modifier.testTag("chart_risk_suggested_lots"))
                                    TextButton(
                                        onClick = { orderVolumeInput = String.format(Locale.US, "%.2f", lots) },
                                        modifier = Modifier.testTag("chart_apply_suggested_lots")
                                    ) {
                                        Text("استخدام الحجم المقترح")
                                    }
                                }
                                if (riskEstimate.maximumLotsForRisk == null) {
                                    Text("ميزانية المخاطرة أقل من الحد الأدنى لحجم العقد",
                                        color = TradingNegative,
                                        modifier = Modifier.testTag("chart_risk_below_minimum"))
                                }
                            }
                            Text("تقدير قبل التنفيذ، لا يشمل الانزلاق والعمولات",
                                fontSize = 11.sp, color = TradingTextSecondary)
                        } else {
                            Text("تعذر حساب المخاطرة بالدولار لهذا الحجم أو الرمز",
                                fontSize = 11.sp, color = TradingNegative)
                        }
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

    pendingAnnotation?.let { drawing ->
        AlertDialog(onDismissRequest = { pendingAnnotation = null },
            title = { Text("تعليق على الشارت") },
            text = { OutlinedTextField(annotationText, { annotationText = it }, singleLine = true) },
            confirmButton = { TextButton(enabled = annotationText.isNotBlank(), onClick = {
                viewModel.addDrawing(drawing.copy(text = annotationText.trim().take(160)))
                pendingAnnotation = null
            }) { Text("حفظ") } },
            dismissButton = { TextButton(onClick = { pendingAnnotation = null }) { Text("إلغاء") } })
    }

    Scaffold(
        modifier = modifier.testTag("chart_screen"),
        containerColor = Color(0xFF020F18),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            if (!immersiveChart) TopAppBar(
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
                                immersiveChart = true
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
                // In standard Replay mode the transport bar already exposes play,
                // stepping and speed. Do not reserve a separate full-width row
                // for another Replay heading unless advanced controls are open.
                if (showReplayDetails) {
                    TextButton(onClick = { showReplayDetails = false }, modifier = Modifier.testTag("chart_replay_expand_btn")) {
                        Text("إخفاء تفاصيل الإعادة ▲", fontSize = 11.sp)
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

            // Show the same supported intervals in the standard strip and immersive menu.
            // Horizontal scrolling preserves legible tap targets on narrow phones.
            if (!immersiveChart) Row(
                modifier = Modifier.fillMaxWidth().height(48.dp)
                    .background(TradingBackground)
                    .horizontalScroll(rememberScrollState())
                    .testTag("chart_timeframe_strip"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                listOf(Timeframe.M1, Timeframe.M3, Timeframe.M5, Timeframe.M15,
                    Timeframe.H1, Timeframe.H2, Timeframe.H4, Timeframe.D1, Timeframe.W1).forEach { tf ->
                    val selected = uiState.selectedTimeframe == tf
                    Column(
                        modifier = Modifier.width(48.dp).fillMaxHeight()
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
                            .background(if (selected) TradingAccent else Color(0xFF263544)))
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

            // Replay indicators only see revealed candles (strict no-lookahead).
            val replaySma = remember(isEmbeddedReplay, replayState.visibleCandles, uiState.indicatorSettings) {
                if (isEmbeddedReplay && uiState.indicatorSettings.isSmaEnabled)
                    com.example.core.indicators.TechnicalIndicators.calculateSma(replayState.visibleCandles, uiState.indicatorSettings.smaPeriod)
                else emptyList()
            }
            val replayEma = remember(isEmbeddedReplay, replayState.visibleCandles, uiState.indicatorSettings) {
                if (isEmbeddedReplay && uiState.indicatorSettings.isEmaEnabled)
                    com.example.core.indicators.TechnicalIndicators.calculateEma(replayState.visibleCandles, uiState.indicatorSettings.emaPeriod)
                else emptyList()
            }
            val replayBollinger = remember(isEmbeddedReplay, replayState.visibleCandles, uiState.indicatorSettings) {
                if (isEmbeddedReplay && uiState.indicatorSettings.isBollingerEnabled)
                    com.example.core.indicators.TechnicalIndicators.calculateBollingerBands(replayState.visibleCandles, uiState.indicatorSettings.bollingerPeriod, uiState.indicatorSettings.bollingerStdDev)
                else emptyList()
            }
            val replayVwap = remember(isEmbeddedReplay, replayState.visibleCandles, uiState.indicatorSettings) {
                if (isEmbeddedReplay && uiState.indicatorSettings.isVwapEnabled)
                    com.example.core.indicators.TechnicalIndicators.calculateVwap(replayState.visibleCandles)
                else emptyList()
            }
            val replayRsi = remember(isEmbeddedReplay, replayState.visibleCandles, uiState.indicatorSettings) {
                if (isEmbeddedReplay && uiState.indicatorSettings.isRsiEnabled)
                    com.example.core.indicators.TechnicalIndicators.calculateRsi(replayState.visibleCandles, uiState.indicatorSettings.rsiPeriod)
                else emptyList()
            }
            val replayMacd = remember(isEmbeddedReplay, replayState.visibleCandles, uiState.indicatorSettings) {
                if (isEmbeddedReplay && uiState.indicatorSettings.isMacdEnabled)
                    com.example.core.indicators.TechnicalIndicators.calculateMacd(replayState.visibleCandles, uiState.indicatorSettings.macdFast, uiState.indicatorSettings.macdSlow, uiState.indicatorSettings.macdSignal)
                else emptyList()
            }
            val replayAtr = remember(isEmbeddedReplay, replayState.visibleCandles, uiState.indicatorSettings) {
                if (isEmbeddedReplay && uiState.indicatorSettings.isAtrEnabled)
                    com.example.core.indicators.TechnicalIndicators.calculateAtr(replayState.visibleCandles, uiState.indicatorSettings.atrPeriod)
                else emptyList()
            }

            // Professional Candlestick Chart
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .onSizeChanged {
                        chartPaletteContainerHeightPx = it.height
                        chartPaletteContainerWidthPx = it.width
                    }
            ) {
                // Reset pan/zoom when the instrument, timeframe, or replay context changes.
                // Do not key on candle data: incoming prices must not jump the viewport.
                key(uiState.selectedSymbol, uiState.selectedTimeframe, isEmbeddedReplay) {
                CandlestickChart(
                    candles = if (isEmbeddedReplay) replayState.visibleCandles else uiState.candles,
                    latestTick = (if (isEmbeddedReplay) replayState.latestTick else uiState.latestTick)
                        ?.takeIf { it.symbol == uiState.selectedSymbol },
                    openPositions = if (isEmbeddedReplay) replayState.openPositions else uiState.openPositions,
                    pendingOrders = if (isEmbeddedReplay) replayState.pendingOrders else uiState.pendingOrders,
                    historicalTrades = if (isEmbeddedReplay) replayState.closedTrades else uiState.historicalTrades,
                    activeDrawingTool = uiState.activeDrawingTool,
                    magnetEnabled = magnetEnabled,
                    drawings = uiState.drawings,
                    indicatorSettings = uiState.indicatorSettings,
                    smaValues = if (isEmbeddedReplay) replaySma else uiState.smaValues,
                    emaValues = if (isEmbeddedReplay) replayEma else uiState.emaValues,
                    bollingerValues = if (isEmbeddedReplay) replayBollinger else uiState.bollingerValues,
                    vwapValues = if (isEmbeddedReplay) replayVwap else uiState.vwapValues,
                    rsiValues = if (isEmbeddedReplay) replayRsi else uiState.rsiValues,
                    macdValues = if (isEmbeddedReplay) replayMacd else uiState.macdValues,
                    atrValues = if (isEmbeddedReplay) replayAtr else uiState.atrValues,
                    isCrosshairActive = uiState.isCrosshairActive,
                    isVolumeVisible = uiState.isVolumeVisible,
                    resetViewTrigger = uiState.resetViewTrigger,
                    displayStyle = chartDisplayStyle,
                    onAddDrawing = {
                        if (it.tool == DrawingTool.ANNOTATION) {
                            annotationText = ""
                            pendingAnnotation = it
                        } else viewModel.addDrawing(it)
                    },
                    onSelectTrade = { viewModel.selectTradeForDetail(it) },
                    onRequestOlderHistory = if (isEmbeddedReplay) null else ({ viewModel.loadOlderChartHistory() }),
                    isLoadingOlderHistory = uiState.isLoadingOlderHistory
                )
                }

                // Historical paging remains available even in immersive mode.
                // It does not replace the chart or navigate away from it.
                if (!isEmbeddedReplay && uiState.candles.isNotEmpty()) {
                    Column(
                        modifier = Modifier.align(Alignment.TopStart)
                            .padding(start = 12.dp, top = 58.dp),
                        horizontalAlignment = Alignment.Start
                    ) {
                        OutlinedButton(
                            onClick = { viewModel.loadOlderChartHistory() },
                            enabled = !uiState.isLoading && !uiState.isLoadingOlderHistory &&
                                uiState.candles.size < 20_000,
                            modifier = Modifier.height(34.dp).testTag("chart_load_older_history"),
                            contentPadding = PaddingValues(horizontal = 9.dp, vertical = 0.dp)
                        ) {
                            Text(
                                if (uiState.isLoadingOlderHistory) "جاري تحميل الأقدم..."
                                else "شموع أقدم · ${uiState.candles.size}",
                                fontSize = 11.sp
                            )
                        }
                        uiState.olderHistoryError?.let { historyError ->
                            Text(historyError, fontSize = 10.sp,
                                color = TradingTextSecondary,
                                modifier = Modifier.widthIn(max = 220.dp))
                        }
                    }
                }

                // Overlay the entry control on the chart instead of reserving a
                // separate row below the candle viewport. Historical prices
                // remain replay-only and never execute as live orders.
                if (!isEmbeddedReplay && uiState.selectedSymbol !in setOf("BTCUSDT", "ETHUSDT")) {
                Button(
                    onClick = {
                        replayViewModel.loadReplayData(uiState.selectedSymbol, uiState.selectedTimeframe)
                        isEmbeddedReplay = true
                                immersiveChart = true
                    },
                    modifier = Modifier
                        // Absolute alignment keeps the control on the physical right
                        // in RTL Arabic layouts (BottomEnd resolves to the left).
                        .align(AbsoluteAlignment.BottomRight)
                        .padding(end = 14.dp, bottom = 110.dp)
                        .height(34.dp)
                        .testTag("chart_start_replay_trading"),
                    shape = RoundedCornerShape(19.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = TradingAccent)
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text("Replay", fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
                }

                // Selectors live exclusively in the bottom strip in the default layout.
                if (immersiveChart) {
                    Row(
                        Modifier.align(Alignment.TopEnd).padding(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(onClick = { viewModel.triggerResetView() }, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Default.North, "إعادة ضبط الشارت", tint = TradingTextPrimary)
                        }
                        IconButton(onClick = { immersiveChart = false }, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Default.FullscreenExit, "عرض التفاصيل", tint = TradingTextPrimary)
                        }
                    }
                }

                // Reference replay transport: compact floating panel with a real timeline.
                if (isEmbeddedReplay && immersiveChart) {
                    Column(
                        modifier = Modifier
                            .align(Alignment.TopCenter)
                            // Keep transport above candles and clear of the left tool rail.
                            .padding(top = 58.dp, start = 76.dp, end = 12.dp)
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(18.dp))
                            .background(TradingCard.copy(alpha = 0.90f))
                            .padding(horizontal = 5.dp, vertical = 3.dp)
                            .testTag("chart_embedded_replay_controls"),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            IconButton(onClick = { showReplayDatePicker = true }, modifier = Modifier.size(34.dp).testTag("chart_replay_date_picker")) {
                                Icon(Icons.Default.History, contentDescription = "تاريخ الإعادة", tint = TradingAccent)
                            }
                            IconButton(onClick = { replayViewModel.stepBackward() },
                                enabled = !replayState.isLoading && replayState.currentIndex > 0,
                                modifier = Modifier.size(34.dp).testTag("chart_replay_step_back")) {
                                Icon(Icons.Default.SkipPrevious, contentDescription = "رجوع شمعة", tint = TradingTextPrimary)
                            }
                            IconButton(onClick = { if (replayState.isPlaying) replayViewModel.pause() else replayViewModel.play() },
                                enabled = !replayState.isLoading && replayState.totalCandles > 0,
                                modifier = Modifier.size(34.dp).testTag("chart_replay_play_pause")) {
                                Icon(if (replayState.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                    contentDescription = "تشغيل أو إيقاف", tint = TradingAccent)
                            }
                            IconButton(onClick = { replayViewModel.stepForward() },
                                enabled = !replayState.isLoading && replayState.currentIndex < replayState.totalCandles - 1,
                                modifier = Modifier.size(34.dp).testTag("chart_replay_step_next")) {
                                Icon(Icons.Default.SkipNext, contentDescription = "تقدم شمعة", tint = TradingTextPrimary)
                            }
                            Box {
                                TextButton(onClick = { replaySpeedMenuExpanded = true }, contentPadding = PaddingValues(horizontal = 0.dp)) {
                                    Text("${replayState.speed}x", color = TradingTextPrimary, fontSize = 12.sp)
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
                                modifier = Modifier.size(32.dp).testTag("chart_replay_close")) {
                                Icon(Icons.Default.Close, contentDescription = "إغلاق الإعادة", tint = TradingTextSecondary)
                            }
                        }
                        val progress = if (replayState.totalCandles > 1)
                            replayState.currentIndex.toFloat().coerceAtLeast(0f) / (replayState.totalCandles - 1)
                        else 0f
                        LinearProgressIndicator(
                            progress = { progress.coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth().height(4.dp)
                                .testTag("chart_replay_timeline"),
                            color = TradingAccent,
                            trackColor = TradingBorder
                        )
                        Text(
                            "${replayState.currentIndex.coerceAtLeast(0) + 1} / ${replayState.totalCandles}",
                            fontSize = 10.sp, color = TradingTextSecondary,
                            modifier = Modifier.testTag("chart_replay_position")
                        )
                    }
                }

                // Minimal source label: historical bars must remain distinguishable
                // from live quotes without covering price candles or indicators.
                val chartBars = if (isEmbeddedReplay) replayState.visibleCandles else uiState.candles
                if (!immersiveChart && chartBars.isNotEmpty()) {
                    Surface(
                        color = TradingBackground.copy(alpha = 0.80f),
                        shape = RoundedCornerShape(6.dp),
                        modifier = Modifier.align(Alignment.TopEnd)
                            .padding(end = 52.dp, top = 6.dp)
                            .testTag("chart_history_provenance")
                    ) {
                        Text(
                            text = if (isEmbeddedReplay) "REPLAY · ${chartBars.size}"
                                else "HISTORICAL · ${chartBars.size}",
                            fontSize = 9.sp,
                            color = TradingTextSecondary,
                            modifier = Modifier.padding(horizontal = 7.dp, vertical = 3.dp)
                        )
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
                // Reference-style drawing controls remain visible over Replay candles.
                Column(
                    modifier = Modifier.align(AbsoluteAlignment.TopLeft)
                        // Physical left, not RTL logical start: keep the price axis clear.
                        .absoluteOffset(
                            x = 8.dp + with(paletteDensity) { drawingPaletteXOffsetPx.toDp() },
                            y = with(paletteDensity) { drawingPaletteOffsetPx.toDp() } +
                                if (isEmbeddedReplay) 148.dp else 52.dp
                        )
                        .onSizeChanged {
                            drawingPaletteHeightPx = it.height
                            drawingPaletteWidthPx = it.width
                        }
                        // Keep each labeled tool visually separate like the reference,
                        // rather than drawing one tall opaque pill across the candles.
                        .width(48.dp)
                        .clip(RoundedCornerShape(24.dp))
                        .background(Color(0xE6081722))
                        .padding(horizontal = 2.dp, vertical = 3.dp)
                        .testTag("chart_reference_floating_tools"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    val referenceTools = listOf(
                        Triple("مؤشر\nمتقاطع", Icons.Default.FilterCenterFocus, 0),
                        Triple("خط اتجاه", Icons.Default.Timeline, 1),
                        Triple("مستوى أفقي", Icons.Default.HorizontalRule, 2),
                        Triple("فيبوناتشي", Icons.Default.AutoGraph, 3),
                        Triple("أشكال", Icons.Default.Category, 4),
                        Triple("تعليق", Icons.Default.Edit, 5),
                        Triple("مستطيل", Icons.Default.CropSquare, 6),
                        Triple("دائرة", Icons.Default.RadioButtonUnchecked, 7),
                        Triple("مغناطيس", Icons.Default.Assistant, 8)
                    )
                    // Dedicated drag handle: tool buttons remain tappable without gesture conflicts.
                    Box(
                        modifier = Modifier
                            .size(width = 46.dp, height = 22.dp)
                            .pointerInput(chartPaletteMaxYOffsetPx, chartPaletteMaxXOffsetPx, isEmbeddedReplay) {
                                detectDragGestures { change, dragAmount ->
                                    change.consume()
                                    // Use the same bounds as the layout resize effect.
                                    // This avoids stale or diverging limits after entering Replay.
                                    drawingPaletteOffsetPx =
                                        (drawingPaletteOffsetPx + dragAmount.y).coerceIn(0f, chartPaletteMaxYOffsetPx)
                                    // Same axis reserve used by resize clamping: 8dp left + 72dp price rail.
                                    drawingPaletteXOffsetPx =
                                        (drawingPaletteXOffsetPx + dragAmount.x).coerceIn(0f, chartPaletteMaxXOffsetPx)
                                }
                            }
                            .testTag("chart_tools_drag_handle"),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.DragHandle, contentDescription = "اسحب لتحريك الأدوات",
                            tint = TradingTextSecondary, modifier = Modifier.size(22.dp))
                    }
                    if (!drawingPaletteCollapsed) referenceTools.forEach { (label, image, index) ->
                        val selected = when (index) {
                            0 -> uiState.isCrosshairActive
                            1 -> uiState.activeDrawingTool == DrawingTool.TRENDLINE
                            2 -> uiState.activeDrawingTool == DrawingTool.HORIZONTAL_LINE
                            3 -> uiState.activeDrawingTool == DrawingTool.FIBONACCI
                            5 -> uiState.activeDrawingTool == DrawingTool.ANNOTATION
                            6 -> uiState.activeDrawingTool == DrawingTool.RECTANGLE
                            7 -> uiState.activeDrawingTool == DrawingTool.ELLIPSE
                            8 -> magnetEnabled
                            else -> false
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Surface(
                                modifier = Modifier.size(32.dp)
                                    .clickable {
                                        when (index) {
                                            0 -> viewModel.toggleCrosshair()
                                            1 -> viewModel.setDrawingTool(DrawingTool.TRENDLINE)
                                            2 -> viewModel.setDrawingTool(DrawingTool.HORIZONTAL_LINE)
                                            3 -> viewModel.setDrawingTool(DrawingTool.FIBONACCI)
                                            4 -> showToolsMenu = true
                                            5 -> viewModel.setDrawingTool(DrawingTool.ANNOTATION)
                                            6 -> viewModel.setDrawingTool(DrawingTool.RECTANGLE)
                                            7 -> viewModel.setDrawingTool(DrawingTool.ELLIPSE)
                                            8 -> magnetEnabled = !magnetEnabled
                                        }
                                    }.testTag("chart_reference_tool_${index}"),
                                shape = RoundedCornerShape(50),
                                // Unified dark tool rail: only the active tool has a visible ring.
                                color = if (selected) TradingAccent.copy(alpha = 0.16f) else Color.Transparent,
                                border = androidx.compose.foundation.BorderStroke(
                                    if (selected) 1.5.dp else 1.dp,
                                    if (selected) TradingAccent else Color(0xFF263544)
                                )
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Icon(image, contentDescription = label,
                                        tint = if (selected) TradingAccent else TradingTextPrimary,
                                        modifier = Modifier.size(19.dp))
                                }
                            }
                            // Reference layout uses visible Arabic captions below each circular tool.
                            // Keep the existing icon content descriptions for accessibility.
                            Text(
                                text = label,
                                fontSize = 9.sp,
                                lineHeight = 11.sp,
                                textAlign = TextAlign.Center,
                                color = if (selected) TradingAccentLight else TradingTextSecondary,
                                modifier = Modifier.width(44.dp)
                                    .background(TradingBackground.copy(alpha = 0.80f), RoundedCornerShape(6.dp))
                            )
                        }
                    }
                    IconButton(
                        onClick = {
                            drawingPaletteCollapsed = !drawingPaletteCollapsed
                            // Keep the palette reachable if expanding makes it taller.
                            drawingPaletteOffsetPx = 0f
                        },
                        modifier = Modifier.size(44.dp).testTag("chart_tools_collapse_toggle")
                    ) {
                        Icon(
                            if (drawingPaletteCollapsed) Icons.Default.ExpandMore else Icons.Default.ExpandLess,
                            contentDescription = if (drawingPaletteCollapsed) "إظهار الأدوات" else "طي الأدوات",
                            tint = TradingTextPrimary
                        )
                    }
                }
            }

            if (immersiveChart) {
                ChartBottomStrip(
                    symbol = uiState.selectedSymbol,
                    timeframe = uiState.selectedTimeframe,
                    replayActive = isEmbeddedReplay,
                    onSymbol = { showSymbolSheet = true },
                    onTimeframe = { tf ->
                        if (tf != uiState.selectedTimeframe) {
                            viewModel.selectTimeframe(tf)
                            if (isEmbeddedReplay) {
                                replayViewModel.pause()
                                replayViewModel.loadReplayData(uiState.selectedSymbol, tf)
                            }
                        }
                    },
                    onReplay = {
                        if (isEmbeddedReplay) {
                            replayViewModel.pause()
                            isEmbeddedReplay = false
                        } else {
                            replayViewModel.loadReplayData(uiState.selectedSymbol, uiState.selectedTimeframe)
                            isEmbeddedReplay = true
                        }
                    },
                    onIndicators = { showIndicatorsDialog = true },
                    onDrawing = { drawingPaletteCollapsed = !drawingPaletteCollapsed },
                    onMore = { showToolsMenu = true }
                )
            }

            if (isEmbeddedReplay && !immersiveChart) {
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

            // Always show Replay BUY/SELL in both immersive and standard chart modes.
            // Previously this row was hidden inside showReplayDetails, which is false
            // by default and whose expand control was itself hidden in immersive mode.
            if (isEmbeddedReplay) {
                // Historical orders use the isolated Replay account, never the live-paper account.
                Row(
                    modifier = Modifier.fillMaxWidth().background(TradingBackground)
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                        .testTag("chart_replay_trading_bar"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    val replayTick = replayState.latestTick
                    val canTradeReplay = !replayState.isLoading &&
                        replayState.currentCandle != null && replayTick != null &&
                        replayTick.symbol == replayState.symbol &&
                        com.example.core.market.DataIntegrityValidator.validateTick(replayTick).isValid
                    Button(
                        onClick = { pendingOrderSide = OrderSide.SELL },
                        enabled = canTradeReplay,
                        colors = ButtonDefaults.buttonColors(containerColor = TradingNegative),
                        modifier = Modifier.weight(1f).height(58.dp).testTag("chart_replay_sell"),
                        shape = RoundedCornerShape(28.dp)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("SELL · بيع", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Text(replayTick?.bid?.let { String.format(Locale.US, "%.2f", it) } ?: "—", fontSize = 17.sp, fontWeight = FontWeight.Bold,
                                style = TextStyle(textDirection = TextDirection.Ltr))
                        }
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        val spreadPips = replayTick?.let { tick ->
                            val pipSize = DefaultSymbols.getSymbol(replayState.symbol).pipSize
                            if (pipSize > 0.0) (tick.ask - tick.bid) / pipSize else null
                        }
                        Text(spreadPips?.let { String.format(Locale.US, "%.1f", it) } ?: "—",
                            color = TradingTextPrimary, fontSize = 12.sp)
                        Text("السبريد", color = TradingTextSecondary, fontSize = 10.sp)
                    }
                    Button(
                        onClick = { pendingOrderSide = OrderSide.BUY },
                        enabled = canTradeReplay,
                        colors = ButtonDefaults.buttonColors(containerColor = TradingPositive),
                        modifier = Modifier.weight(1f).height(58.dp).testTag("chart_replay_buy"),
                        shape = RoundedCornerShape(28.dp)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("BUY · شراء", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Text(replayTick?.ask?.let { String.format(Locale.US, "%.2f", it) } ?: "—", fontSize = 17.sp, fontWeight = FontWeight.Bold,
                                style = TextStyle(textDirection = TextDirection.Ltr))
                        }
                    }

                }
                if (replayState.openPositions.isNotEmpty()) {
                    Text(
                        "مراكز مفتوحة: ${replayState.openPositions.size} · رصيد: ${String.format(Locale.US, "%.2f", replayState.currentBalance)}",
                        color = TradingTextSecondary,
                        fontSize = 11.sp,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp)
                            .testTag("chart_replay_open_positions_summary")
                    )
                }
            }

            // No executable bid/ask exists for historical-only metals and forex.
            // Keep their chart unobstructed; show execution only for crypto.
            if (!isEmbeddedReplay && uiState.selectedSymbol in setOf("BTCUSDT", "ETHUSDT")) Surface(
                color = TradingCard,
                tonalElevation = 0.dp,
                border = androidx.compose.foundation.BorderStroke(1.dp, TradingBorder)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
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
                            .height(64.dp)
                            .testTag("chart_quick_sell_btn"),
                        shape = RoundedCornerShape(28.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingNegative)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("بيع", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                            Text(bidText, style = TextStyle(textDirection = TextDirection.Ltr, textAlign = TextAlign.Center), maxLines = 1, fontSize = 17.sp, fontWeight = FontWeight.Bold)
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
                            .height(64.dp)
                            .testTag("chart_quick_buy_btn"),
                        shape = RoundedCornerShape(28.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingPositive)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("شراء", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                            Text(askText, style = TextStyle(textDirection = TextDirection.Ltr, textAlign = TextAlign.Center), maxLines = 1, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }

    // Centered symbol selector keeps the chart visible behind the popup.
    if (showSymbolSheet) {
        Dialog(onDismissRequest = { showSymbolSheet = false }) {
            Column(
                modifier = Modifier
                    .widthIn(max = 290.dp)
                    .heightIn(max = 430.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(TradingCard.copy(alpha = 0.97f))
                    .testTag("chart_symbol_popup")
                    .padding(vertical = 10.dp)
            ) {
                Text(
                    text = "تبديل الزوج",
                    color = TradingTextPrimary,
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
                OutlinedTextField(
                    value = symbolSearchQuery,
                    onValueChange = { symbolSearchQuery = it },
                    label = { Text("بحث عن زوج أو اسم") },
                    singleLine = true,
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp).testTag("chart_symbol_search")
                )
                val categories = listOf("الكل") + DefaultSymbols.SYMBOLS.map { it.category }.distinct()
                Row(
                    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 10.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    FilterChip(
                        selected = recentOnly,
                        onClick = { recentOnly = !recentOnly },
                        label = { Text("الأخيرة", fontSize = 11.sp) },
                        modifier = Modifier.testTag("chart_symbol_recent_filter")
                    )
                    FilterChip(
                        selected = favoritesOnly,
                        onClick = { favoritesOnly = !favoritesOnly },
                        label = { Text("★ المفضلة", fontSize = 11.sp) },
                        modifier = Modifier.testTag("chart_symbol_favorites_filter")
                    )
                    categories.forEach { category ->
                        FilterChip(
                            selected = symbolCategoryFilter == category,
                            onClick = { symbolCategoryFilter = category },
                            label = { Text(category, maxLines = 1, fontSize = 11.sp) }
                        )
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("المفضلة أولاً", fontSize = 12.sp, color = TradingTextSecondary)
                    Switch(
                        checked = symbolSortFavoritesFirst,
                        onCheckedChange = { symbolSortFavoritesFirst = it },
                        modifier = Modifier.testTag("chart_symbol_sort_favorites")
                    )
                }
                HorizontalDivider(color = TradingBorder)
                val filteredSymbols = DefaultSymbols.SYMBOLS.filter { sym ->
                    (!recentOnly || sym.symbol in recentSymbols) &&
                    (!favoritesOnly || sym.symbol in favoriteSymbols) &&
                    (symbolCategoryFilter == "الكل" || sym.category == symbolCategoryFilter) &&
                        (symbolSearchQuery.isBlank() || sym.symbol.contains(symbolSearchQuery.trim(), ignoreCase = true) ||
                            sym.name.contains(symbolSearchQuery.trim(), ignoreCase = true))
                }.let { matches ->
                    if (symbolSortFavoritesFirst) matches.sortedByDescending { it.symbol in favoriteSymbols } else matches
                }
                Text(
                    text = "النتائج: " + filteredSymbols.size + " / " + DefaultSymbols.SYMBOLS.size,
                    color = TradingTextSecondary,
                    fontSize = 11.sp,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)
                        .testTag("chart_symbol_result_count")
                )
                Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    if (filteredSymbols.isEmpty()) {
                        Text("لا توجد أزواج مطابقة", color = TradingTextSecondary,
                            modifier = Modifier.padding(16.dp).testTag("chart_symbol_empty"))
                    }
                    filteredSymbols.forEach { sym ->
                        val selected = sym.symbol == uiState.selectedSymbol
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(if (selected) TradingAccentLight.copy(alpha = 0.14f) else Color.Transparent)
                                .clickable {
                                    recentSymbols = ArrayList(
                                        (listOf(sym.symbol) + recentSymbols.filter { it != sym.symbol }).take(8)
                                    )
                                    viewModel.selectSymbol(sym.symbol)
                                    showSymbolSheet = false
                                }
                                .testTag("chart_symbol_option_" + sym.symbol)
                                .padding(horizontal = 16.dp, vertical = 11.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = sym.symbol,
                                    style = TextStyle(textDirection = TextDirection.Ltr),
                                    fontWeight = if (selected) FontWeight.ExtraBold else FontWeight.Medium,
                                    fontSize = 16.sp,
                                    color = if (selected) TradingAccentLight else TradingTextPrimary
                                )
                                Text(text = sym.name, fontSize = 11.sp, color = TradingTextSecondary, maxLines = 1)
                            }
                            IconButton(
                                onClick = {
                                    favoriteSymbolsList = ArrayList(
                                        if (sym.symbol in favoriteSymbols) favoriteSymbols - sym.symbol
                                        else favoriteSymbols + sym.symbol
                                    )
                                },
                                modifier = Modifier.size(36.dp).testTag("chart_symbol_favorite_" + sym.symbol)
                            ) {
                                Icon(
                                    if (sym.symbol in favoriteSymbols) Icons.Default.Star else Icons.Default.StarBorder,
                                    contentDescription = if (sym.symbol in favoriteSymbols) "إزالة من المفضلة" else "إضافة للمفضلة",
                                    tint = if (sym.symbol in favoriteSymbols) TradingAccentLight else TradingTextSecondary,
                                    modifier = Modifier.size(19.dp)
                                )
                            }
                            if (selected) {
                                Icon(Icons.Default.Check, contentDescription = "الزوج المحدد", tint = TradingAccentLight, modifier = Modifier.size(20.dp))
                            }
                        }
                    }
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
