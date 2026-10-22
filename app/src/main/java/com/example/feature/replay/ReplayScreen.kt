package com.example.feature.replay

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.feature.chart.ChartIndicatorsDialog
import com.example.feature.chart.model.IndicatorSettings
import com.example.feature.chart.model.DrawingTool
import com.example.feature.chart.model.ChartDrawing
import com.example.core.model.DataSourceType
import com.example.core.model.OrderSide
import com.example.core.model.OrderType
import com.example.core.model.PositionSide
import com.example.core.model.Timeframe
import com.example.ui.components.CandlestickChart
import com.example.ui.components.ChartDisplayStyle
import com.example.ui.components.DataSourceBadge
import com.example.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReplayScreen(
    viewModel: ReplayViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val clipboardManager = LocalClipboardManager.current
    val dateFormat = remember { SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US) }
    var showJumpDialog by remember { mutableStateOf(false) }
    var chartFocusMode by remember { mutableStateOf(false) }
    var showChartTools by remember { mutableStateOf(true) }
    var showDrawingTools by remember { mutableStateOf(false) }
    var showHistoryDialog by remember { mutableStateOf(false) }
    var showMarketDialog by remember { mutableStateOf(false) }
    var showIndicatorsDialog by remember { mutableStateOf(false) }
    var indicatorSettings by remember { mutableStateOf(IndicatorSettings()) }
    // Heavy calculations run off the Compose/UI thread. produceState cancels
    // stale work when replay advances, rewinds or indicator settings change.
    // Null results hide stale indicator lines until the matching set is ready.
    val indicatorSnapshot by produceState<ReplayIndicatorSnapshot?>(
        initialValue = null,
        key1 = uiState.visibleCandles,
        key2 = indicatorSettings
    ) {
        value = null
        val revealed = uiState.visibleCandles
        val selected = indicatorSettings
        value = withContext(Dispatchers.Default) {
            ReplayIndicatorSnapshot.calculate(revealed, selected)
        }
    }

    var crosshairEnabled by remember { mutableStateOf(false) }
    var activeDrawingTool by remember { mutableStateOf(DrawingTool.NONE) }
    val replayDrawings = remember(uiState.symbol, uiState.timeframe) { mutableStateListOf<ChartDrawing>() }
    LaunchedEffect(uiState.symbol, uiState.timeframe) {
        activeDrawingTool = DrawingTool.NONE
        crosshairEnabled = false
    }
    val revealedDrawings = visibleReplayDrawings(replayDrawings, uiState.currentCandle?.openTime)
    var volumeVisible by remember { mutableStateOf(true) }
    var replayChartStyle by remember { mutableStateOf(ChartDisplayStyle.CANDLES) }
    var chartResetTrigger by remember { mutableLongStateOf(0L) }
    var showOrderTicket by remember { mutableStateOf(false) }
    var showPerformanceDialog by remember { mutableStateOf(false) }
    var showAuditDialog by remember { mutableStateOf(false) }
    var showDrawdownChart by remember { mutableStateOf(false) }
    var showRiskDialog by remember { mutableStateOf(false) }
    var riskPositions by remember { mutableStateOf("10") }
    var riskOrders by remember { mutableStateOf("20") }
    var riskDrawdown by remember { mutableStateOf("100") }
    var riskEnabled by remember { mutableStateOf(true) }
    var riskConsecutiveLosses by remember { mutableStateOf("0") }
    var riskSessionLoss by remember { mutableStateOf("0") }
    var editProtectionId by remember { mutableStateOf<Long?>(null) }
    var editSl by remember { mutableStateOf("") }
    var editTp by remember { mutableStateOf("") }
    var ticketSide by remember { mutableStateOf(OrderSide.BUY) }
    var ticketType by remember { mutableStateOf(OrderType.BUY_LIMIT) }
    var ticketVolume by remember { mutableStateOf("0.01") }
    var ticketPrice by remember { mutableStateOf("") }
    var ticketSl by remember { mutableStateOf("") }
    var ticketTp by remember { mutableStateOf("") }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(uiState.message) {
        uiState.message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearMessage()
        }
    }

    Scaffold(
        modifier = modifier.testTag("replay_screen"),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "محاكي الإعادة التاريخية",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        DataSourceBadge(sourceType = DataSourceType.REPLAY_DATA)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
                    }
                },
                actions = {
                    IconButton(
                        onClick = { showAuditDialog = true },
                        modifier = Modifier.testTag("replay_data_audit_btn")
                    ) {
                        Icon(Icons.Default.FactCheck, contentDescription = "تدقيق بيانات Replay", tint = TradingAccentLight)
                    }
                    IconButton(
                        onClick = { chartFocusMode = !chartFocusMode },
                        modifier = Modifier.testTag("replay_chart_focus_btn")
                    ) {
                        Icon(
                            if (chartFocusMode) Icons.Default.FullscreenExit else Icons.Default.Fullscreen,
                            contentDescription = if (chartFocusMode) "الخروج من وضع الشارت الموسع" else "تكبير الشارت",
                            tint = TradingAccentLight
                        )
                    }
                    IconButton(onClick = {
                        riskPositions = uiState.maxOpenPositions.toString()
                        riskOrders = uiState.maxPendingOrders.toString()
                        riskDrawdown = uiState.maxDrawdownPercent.toString()
                        riskEnabled = uiState.riskGuardEnabled
                        riskConsecutiveLosses = uiState.maxConsecutiveLosses.toString()
                        riskSessionLoss = uiState.maxSessionLossUsd.toString()
                        showRiskDialog = true
                    }, modifier = Modifier.testTag("replay_risk_btn")) {
                        Icon(Icons.Default.Security, contentDescription = "إدارة مخاطر Replay", tint = TradingAccentLight)
                    }
                    IconButton(onClick = { showPerformanceDialog = true }, modifier = Modifier.testTag("replay_performance_btn")) {
                        Icon(Icons.Default.Assessment, contentDescription = "نتائج الباك تيست", tint = TradingAccentLight)
                    }
                    IconButton(onClick = { showMarketDialog = true }, modifier = Modifier.testTag("replay_market_btn")) {
                        Icon(Icons.Default.Tune, contentDescription = "الزوج والإطار الزمني", tint = TradingAccentLight)
                    }
                    IconButton(onClick = { showHistoryDialog = true }, modifier = Modifier.testTag("replay_history_btn")) {
                        Icon(Icons.Default.History, contentDescription = "نطاق البيانات التاريخية", tint = TradingAccentLight)
                    }
                    IconButton(onClick = { showJumpDialog = true }, modifier = Modifier.testTag("replay_jump_btn")) {
                        Icon(Icons.Default.DateRange, contentDescription = "قفز لتاريخ", tint = TradingAccentLight)
                    }
                    IconButton(onClick = { viewModel.resetReplay() }, modifier = Modifier.testTag("replay_restart_btn")) {
                        Icon(Icons.Default.RestartAlt, contentDescription = "إعادة البدء")
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
            // 1. Mandatory Historical Replay Zero Lookahead Info Banner
            Surface(
                color = TradingCard,
                modifier = Modifier.fillMaxWidth(),
                tonalElevation = 2.dp,
                border = androidx.compose.foundation.BorderStroke(1.dp, TradingBorder)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        val dateText = uiState.currentCandle?.let { dateFormat.format(Date(it.openTime)) } ?: "--"
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(text = "${uiState.symbol} (${uiState.timeframe.displayName})", fontWeight = FontWeight.Bold, fontSize = 12.sp)
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(text = "• $dateText", fontSize = 11.sp, color = TradingTextSecondary)
                        }
                        val remaining = (uiState.totalCandles - (uiState.currentIndex + 1)).coerceAtLeast(0)
                        Text(
                            text = "شمعة ${uiState.currentIndex + 1} من ${uiState.totalCandles} (متبقي $remaining)",
                            fontSize = 10.sp,
                            color = TradingTextMuted
                        )
                    }

                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            text = String.format(Locale.US, "الرصيد: $%.2f", uiState.currentBalance),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = TradingTextPrimary
                        )
                        val eq = uiState.currentEquity
                        val isProfit = eq >= uiState.initialBalance
                        Text(
                            text = String.format(Locale.US, "الملكية: $%.2f", eq),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isProfit) TradingPositive else TradingNegative
                        )
                    }
                }
            }

            if (!chartFocusMode) {
            val riskStatus = viewModel.currentRiskBlockReason()
            if (riskStatus != null && !uiState.isLoading) {
                Surface(color = TradingNegative.copy(alpha = 0.12f), modifier = Modifier.fillMaxWidth()) {
                    Text(
                        "حماية المخاطر: $riskStatus",
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 5.dp),
                        fontSize = 11.sp,
                        color = TradingNegative
                    )
                }
            }
            // Mode Toggle: MANUAL vs STRATEGY
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(
                        Pair(ReplayInteractionMode.MANUAL, "تداول يدوي"),
                        Pair(ReplayInteractionMode.STRATEGY, "استراتيجية تلقائية")
                    ).forEach { (m, label) ->
                        val isSel = uiState.interactionMode == m
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(if (isSel) TradingAccent else TradingElevated)
                                .clickable { viewModel.setInteractionMode(m) }
                                .padding(horizontal = 10.dp, vertical = 4.dp)
                        ) {
                            Text(
                                text = label,
                                fontSize = 11.sp,
                                fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal,
                                color = if (isSel) Color.White else TradingTextSecondary
                            )
                        }
                    }
                }

                uiState.lastSignalMessage?.let { sig ->
                    Text(
                        text = sig,
                        fontSize = 10.sp,
                        color = TradingCyan,
                        maxLines = 1
                    )
                }
            }

            }
            // Replay chart tools stay on the chart screen; no separate replay chart page.
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = { showChartTools = !showChartTools }, modifier = Modifier.testTag("replay_toggle_chart_tools")) {
                    Text(if (showChartTools) "إخفاء أدوات الشارت" else "أدوات الشارت", fontSize = 11.sp)
                }
                TextButton(onClick = { showDrawingTools = !showDrawingTools }, modifier = Modifier.testTag("replay_toggle_drawing_tools")) {
                    Text(if (showDrawingTools) "إخفاء الرسم" else "أدوات الرسم", fontSize = 11.sp)
                }
            }
            if (showChartTools) {
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                    .padding(horizontal = 10.dp, vertical = 3.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                FilterChip(
                    selected = crosshairEnabled,
                    onClick = {
                        crosshairEnabled = !crosshairEnabled
                        if (crosshairEnabled) activeDrawingTool = DrawingTool.NONE
                    },
                    label = { Text("مؤشر التقاطع", fontSize = 11.sp) },
                    modifier = Modifier.testTag("replay_crosshair_toggle")
                )
                FilterChip(
                    selected = volumeVisible,
                    onClick = { volumeVisible = !volumeVisible },
                    label = { Text("الحجم", fontSize = 11.sp) },
                    modifier = Modifier.testTag("replay_volume_toggle")
                )
                TextButton(onClick = { showIndicatorsDialog = true }, modifier = Modifier.testTag("replay_indicators_btn")) {
                    Text("المؤشرات", fontSize = 11.sp)
                }
                ChartDisplayStyle.entries.forEach { style ->
                    FilterChip(
                        selected = replayChartStyle == style,
                        onClick = { replayChartStyle = style },
                        label = { Text(style.label, fontSize = 11.sp) },
                        modifier = Modifier.testTag("replay_chart_style_${style.name.lowercase(Locale.US)}")
                    )
                }
                TextButton(
                    onClick = { chartResetTrigger++ },
                    modifier = Modifier.testTag("replay_chart_reset")
                ) { Text("إعادة ضبط الشارت", fontSize = 11.sp) }
            }

            }
            if (showDrawingTools) {
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                    .padding(horizontal = 10.dp, vertical = 2.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                DrawingTool.entries.forEach { tool ->
                    FilterChip(
                        selected = activeDrawingTool == tool,
                        onClick = {
                            activeDrawingTool = tool
                            if (tool != DrawingTool.NONE) crosshairEnabled = false
                        },
                        label = { Text(tool.displayNameAr, fontSize = 10.sp) },
                        modifier = Modifier.testTag("replay_drawing_${tool.name.lowercase(Locale.US)}")
                    )
                }
                TextButton(
                    enabled = revealedDrawings.isNotEmpty(),
                    onClick = { revealedDrawings.lastOrNull()?.let { replayDrawings.remove(it) } },
                    modifier = Modifier.testTag("replay_drawing_undo")
                ) { Text("تراجع عن الرسم") }
                TextButton(
                    enabled = replayDrawings.isNotEmpty(),
                    onClick = { replayDrawings.clear() },
                    modifier = Modifier.testTag("replay_drawing_clear")
                ) { Text("مسح الرسومات") }
            }

            }
            // 2. Large Central Candlestick Chart (Zero future candles, strictly visible subset!)
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                CandlestickChart(
                    candles = uiState.visibleCandles,
                    latestTick = uiState.latestTick,
                    openPositions = uiState.openPositions,
                    pendingOrders = uiState.pendingOrders,
                    historicalTrades = uiState.closedTrades,
                    isCrosshairActive = crosshairEnabled,
                    isVolumeVisible = volumeVisible,
                    resetViewTrigger = chartResetTrigger,
                    activeDrawingTool = activeDrawingTool,
                    drawings = revealedDrawings,
                    onAddDrawing = { drawing ->
                        if (drawing.startPrice.isFinite() && drawing.startPrice > 0.0 &&
                            (drawing.endPrice == null || (drawing.endPrice.isFinite() && drawing.endPrice > 0.0)) &&
                            drawing.startTime <= (uiState.currentCandle?.openTime ?: Long.MIN_VALUE) &&
                            (drawing.endTime == null || drawing.endTime <= (uiState.currentCandle?.openTime ?: Long.MIN_VALUE))) {
                            replayDrawings.add(drawing.copy(
                                id = (replayDrawings.lastOrNull()?.id ?: 0L) + 1L,
                                symbol = uiState.symbol,
                                timeframe = uiState.timeframe.name
                            ))
                        }
                    },
                    displayStyle = replayChartStyle,
                    indicatorSettings = indicatorSettings,
                    smaValues = indicatorSnapshot?.sma ?: emptyList(),
                    emaValues = indicatorSnapshot?.ema ?: emptyList(),
                    bollingerValues = indicatorSnapshot?.bollinger ?: emptyList(),
                    vwapValues = indicatorSnapshot?.vwap ?: emptyList(),
                    rsiValues = indicatorSnapshot?.rsi ?: emptyList(),
                    macdValues = indicatorSnapshot?.macd ?: emptyList(),
                    atrValues = indicatorSnapshot?.atr ?: emptyList()
                )
            }

            if (chartFocusMode) {
                Surface(color = TradingCard, modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 3.dp),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(onClick = { viewModel.stepBackward() }, modifier = Modifier.testTag("replay_focus_previous")) {
                            Icon(Icons.Default.SkipPrevious, contentDescription = "الشمعة السابقة")
                        }
                        IconButton(onClick = { if (uiState.isPlaying) viewModel.pause() else viewModel.play() },
                            modifier = Modifier.testTag("replay_focus_play_pause")) {
                            Icon(if (uiState.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, contentDescription = "تشغيل أو إيقاف")
                        }
                        IconButton(onClick = { viewModel.stepForward() }, modifier = Modifier.testTag("replay_focus_next")) {
                            Icon(Icons.Default.SkipNext, contentDescription = "الشمعة التالية")
                        }
                        Text(
                            "${uiState.currentIndex + 1}/${uiState.totalCandles}",
                            fontSize = 11.sp, color = TradingTextSecondary
                        )
                        TextButton(onClick = { chartFocusMode = false }) { Text("تداول") }
                    }
                }
            }
            if (!chartFocusMode) {
            // 3. Playback Controls & Speed Selector
            Surface(
                color = TradingCard,
                border = androidx.compose.foundation.BorderStroke(1.dp, TradingBorder)
            ) {
                Column(modifier = Modifier.heightIn(max = 330.dp).verticalScroll(rememberScrollState()).padding(10.dp)) {
                    // Replay Speed Selector: 0.5x, 1x, 2x, 5x, 10x, 25x, 50x, 100x
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        listOf(0.5f, 1f, 2f, 5f, 10f, 25f, 50f, 100f).forEach { s ->
                            val isSel = uiState.speed == s
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (isSel) TradingAccent else TradingElevated)
                                    .clickable { viewModel.setSpeed(s) }
                                    .padding(horizontal = 8.dp, vertical = 4.dp)
                                    .testTag("speed_${s}x")
                            ) {
                                Text(
                                    text = "${s}x",
                                    fontSize = 11.sp,
                                    fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal,
                                    color = if (isSel) Color.White else TradingTextSecondary
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    // Player buttons: Previous (Safe Rewind), Play/Pause, Next (One Candle)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(
                            onClick = { viewModel.stepBackward() },
                            modifier = Modifier.testTag("replay_step_back_btn")
                        ) {
                            Icon(Icons.Default.SkipPrevious, contentDescription = "الشمعة السابقة (تراجع آمن)", tint = TradingTextPrimary)
                        }

                        FilledIconButton(
                            onClick = {
                                if (uiState.isPlaying) viewModel.pause() else viewModel.play()
                            },
                            colors = IconButtonDefaults.filledIconButtonColors(containerColor = TradingAccent),
                            modifier = Modifier.size(48.dp).testTag("replay_play_pause_btn")
                        ) {
                            Icon(
                                imageVector = if (uiState.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                contentDescription = if (uiState.isPlaying) "إيقاف مؤقت" else "تشغيل"
                            )
                        }

                        IconButton(
                            onClick = { viewModel.stepForward() },
                            modifier = Modifier.testTag("replay_step_next_btn")
                        ) {
                            Icon(Icons.Default.SkipNext, contentDescription = "الشمعة التالية (Next Candle)", tint = TradingTextPrimary)
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    if (uiState.openPositions.isNotEmpty()) {
                        Text("الصفقات المفتوحة", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        uiState.openPositions.forEach { position ->
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp)
                                    .testTag("replay_position_${position.id}")
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        "${position.symbol}  ${position.side.name}  ${position.volume}",
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                    Text(
                                        String.format(Locale.US, "%+.2f USD", position.profitLoss),
                                        fontSize = 11.sp,
                                        color = if (position.profitLoss >= 0.0) TradingPositive else TradingNegative
                                    )
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        "دخول: ${String.format(Locale.US, "%.2f", position.entryPrice)}" +
                                            "  SL: ${position.stopLoss?.let { String.format(Locale.US, "%.2f", it) } ?: "—"}" +
                                            "  TP: ${position.takeProfit?.let { String.format(Locale.US, "%.2f", it) } ?: "—"}",
                                        fontSize = 10.sp,
                                        color = TradingTextSecondary
                                    )
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    TextButton(
                                        onClick = {
                                            editProtectionId = position.id
                                            editSl = position.stopLoss?.toString() ?: ""
                                            editTp = position.takeProfit?.toString() ?: ""
                                        },
                                        modifier = Modifier.testTag("replay_edit_protection_${position.id}")
                                    ) { Text("تعديل SL/TP") }
                                    TextButton(
                                        onClick = { viewModel.setBreakEven(position.id) },
                                        modifier = Modifier.testTag("replay_breakeven_${position.id}")
                                    ) { Text("نقطة التعادل") }
                                    TextButton(
                                        onClick = { viewModel.closePosition(position.id) },
                                        modifier = Modifier.testTag("replay_close_${position.id}")
                                    ) { Text("إغلاق الصفقة", color = TradingNegative) }
                                }
                            }
                        }
                    }

                    OutlinedButton(
                        onClick = { showOrderTicket = true },
                        modifier = Modifier.fillMaxWidth().testTag("replay_pending_ticket_btn")
                    ) { Text("أمر معلق LIMIT / STOP") }
                    if (uiState.pendingOrders.isNotEmpty()) {
                        Text("الأوامر المعلقة", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        uiState.pendingOrders.forEach { order ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("${order.type.name}  ${order.requestedPrice}", fontSize = 11.sp)
                                TextButton(onClick = { viewModel.cancelPendingOrder(order.id) }) {
                                    Text("إلغاء #${order.id}")
                                }
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    // 4. Quick Replay BUY / SELL Manual Controls (Evaluates at Replay Time T)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        val bidText = uiState.latestTick?.let { String.format(Locale.US, "%.2f", it.bid) } ?: "--"
                        Button(
                            onClick = { viewModel.executeOrder(OrderSide.SELL, 0.01) },
                            modifier = Modifier.weight(1f).height(44.dp).testTag("replay_sell_btn"),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = TradingNegative)
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("بيع Replay SELL", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                Text(bidText, fontSize = 10.sp)
                            }
                        }

                        val askText = uiState.latestTick?.let { String.format(Locale.US, "%.2f", it.ask) } ?: "--"
                        Button(
                            onClick = { viewModel.executeOrder(OrderSide.BUY, 0.01) },
                            modifier = Modifier.weight(1f).height(44.dp).testTag("replay_buy_btn"),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = TradingPositive)
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("شراء Replay BUY", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                Text(askText, fontSize = 10.sp)
                            }
                        }
                    }
                }
            }
            }
        }
    }

    if (showRiskDialog) {
        val validPositions = riskPositions.toIntOrNull()?.takeIf { it in 1..100 }
        val validOrders = riskOrders.toIntOrNull()?.takeIf { it in 1..200 }
        val validDrawdown = riskDrawdown.toDoubleOrNull()?.takeIf { it.isFinite() && it in 1.0..100.0 }
        val validLossStreak = riskConsecutiveLosses.toIntOrNull()?.takeIf { it in 0..100 }
        val validSessionLoss = riskSessionLoss.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0.0 }
        AlertDialog(
            onDismissRequest = { showRiskDialog = false },
            title = { Text("إدارة مخاطر Replay") },
            text = {
                Column(
                    modifier = Modifier.heightIn(max = 460.dp).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = riskEnabled, onCheckedChange = { riskEnabled = it })
                        Text("تفعيل حواجز المخاطر", fontSize = 12.sp)
                    }
                    Text("الحدود تمنع فتح صفقات أو أوامر جديدة عند تجاوزها؛ لا تغلق المراكز القائمة تلقائيًا.", fontSize = 12.sp, color = TradingTextSecondary)
                    OutlinedTextField(
                        value = riskPositions,
                        onValueChange = { riskPositions = it },
                        label = { Text("الحد الأقصى للصفقات المفتوحة (1–100)") },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = riskOrders,
                        onValueChange = { riskOrders = it },
                        label = { Text("الحد الأقصى للأوامر المعلقة (1–200)") },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = riskDrawdown,
                        onValueChange = { riskDrawdown = it },
                        label = { Text("حد التراجع من رأس المال الابتدائي % (1–100)") },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = riskConsecutiveLosses,
                        onValueChange = { riskConsecutiveLosses = it },
                        label = { Text("الخسائر المتتالية (0 = بدون حد)") },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = riskSessionLoss,
                        onValueChange = { riskSessionLoss = it },
                        label = { Text("حد الخسارة المحققة بالدولار (0 = بدون حد)") },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = validPositions != null && validOrders != null && validDrawdown != null &&
                        validLossStreak != null && validSessionLoss != null,
                    onClick = {
                        viewModel.configureRiskLimits(validPositions!!, validOrders!!, validDrawdown!!)
                        viewModel.configureExtendedRiskLimits(riskEnabled, validLossStreak!!, validSessionLoss!!)
                        showRiskDialog = false
                    }
                ) { Text("تطبيق الحدود") }
            },
            dismissButton = { TextButton(onClick = { showRiskDialog = false }) { Text("إلغاء") } }
        )
    }

    if (showAuditDialog) {
        val audit = remember(uiState.visibleCandles, uiState.timeframe) {
            ReplaySessionAudit.inspect(uiState.visibleCandles, uiState.timeframe.minutes)
        }
        AlertDialog(
            onDismissRequest = { showAuditDialog = false },
            title = { Text("تدقيق بيانات Replay") },
            text = {
                Column(
                    modifier = Modifier.verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text("فحص الشموع التي كُشفت حتى الآن فقط، دون الاطلاع على شموع المستقبل.",
                        fontSize = 12.sp, color = TradingTextSecondary)
                    ReplayMetricRow("حالة البيانات", if (audit.isClean) "سليمة في النطاق المفحوص" else "توجد ملاحظات")
                    ReplayMetricRow("الشموع المفحوصة", audit.candleCount.toString())
                    ReplayMetricRow("أول شمعة مفحوصة", audit.firstOpenTime?.let { dateFormat.format(Date(it)) } ?: "—")
                    ReplayMetricRow("آخر شمعة مفحوصة", audit.lastOpenTime?.let { dateFormat.format(Date(it)) } ?: "—")
                    ReplayMetricRow("نسبة تقدم الجلسة",
                        if (uiState.totalCandles > 0) String.format(Locale.US, "%.1f%%",
                            (uiState.currentIndex + 1) * 100.0 / uiState.totalCandles) else "—")
                    ReplayMetricRow("أسعار غير صالحة", audit.invalidPrices.toString())
                    ReplayMetricRow("نطاقات OHLC غير صحيحة", audit.invalidRanges.toString())
                    ReplayMetricRow("تكرار أو اختلال الترتيب", audit.duplicateOrOutOfOrder.toString())
                    ReplayMetricRow("فجوات زمنية", audit.intervalGaps.toString())
                    ReplayMetricRow("شموع مفقودة تقديريًا", audit.missingBars.toString())
                    ReplayMetricRow("قيم حجم غير صالحة", audit.volumeAnomalies.toString())
                    Text("هذا الفحص لا يثبت تطابق الأسعار مع TradingView أو MT5.",
                        fontSize = 11.sp, color = TradingTextSecondary)
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        clipboardManager.setText(AnnotatedString(
                            ReplaySessionAudit.exportCsv(audit, uiState.symbol, uiState.timeframe.name)
                        ))
                    },
                    modifier = Modifier.testTag("replay_copy_audit_csv")
                ) { Text("نسخ تقرير CSV") }
            },
            dismissButton = { TextButton(onClick = { showAuditDialog = false }) { Text("إغلاق") } }
        )
    }

    if (showPerformanceDialog) {
        val trades = uiState.closedTrades
        val report = remember(trades, uiState.equitySamples, uiState.currentEquity, uiState.initialBalance) {
            ReplayPerformanceAnalytics.calculate(trades, uiState.equitySamples, uiState.initialBalance, uiState.currentEquity)
        }
        val net = trades.sumOf { it.netProfitLoss }
        val winners = trades.count { it.netProfitLoss > 0.0 }
        val losers = trades.count { it.netProfitLoss < 0.0 }
        val grossProfit = trades.filter { it.netProfitLoss > 0.0 }.sumOf { it.netProfitLoss }
        val grossLoss = -trades.filter { it.netProfitLoss < 0.0 }.sumOf { it.netProfitLoss }
        val winRate = if (trades.isEmpty()) 0.0 else winners * 100.0 / trades.size
        val profitFactor = if (grossLoss > 0.0) grossProfit / grossLoss else null
        val returnPercent = if (uiState.initialBalance > 0.0) {
            (uiState.currentEquity - uiState.initialBalance) * 100.0 / uiState.initialBalance
        } else 0.0
        AlertDialog(
            onDismissRequest = { showPerformanceDialog = false },
            title = { Text("نتائج جلسة Replay") },
            text = {
                Column(
                    modifier = Modifier.verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("إحصاءات الصفقات المغلقة فقط؛ العائد يشمل الملكية الحالية للصفقات المفتوحة.", fontSize = 12.sp, color = TradingTextSecondary)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(
                            selected = !showDrawdownChart,
                            onClick = { showDrawdownChart = false },
                            label = { Text("الملكية") },
                            modifier = Modifier.testTag("replay_equity_chart_mode")
                        )
                        FilterChip(
                            selected = showDrawdownChart,
                            onClick = { showDrawdownChart = true },
                            label = { Text("التراجع") },
                            modifier = Modifier.testTag("replay_drawdown_chart_mode")
                        )
                    }
                    ReplayEquityCurve(
                        samples = uiState.equitySamples,
                        initialBalance = uiState.initialBalance,
                        modifier = Modifier.fillMaxWidth(),
                        showDrawdown = showDrawdownChart
                    )
                    HorizontalDivider()
                    ReplayMetricRow("الصفقات المغلقة", trades.size.toString())
                    ReplayMetricRow("التعادل", report.breakeven.toString())
                    ReplayMetricRow("متوسط الصفقة", String.format(Locale.US, "%+.2f USD", report.averageTrade))
                    ReplayMetricRow("متوسط الربح", String.format(Locale.US, "%.2f USD", report.averageWin))
                    ReplayMetricRow("متوسط الخسارة", String.format(Locale.US, "%.2f USD", report.averageLoss))
                    ReplayMetricRow("العائد إلى المخاطرة المحققة", report.payoffRatio?.let {
                        String.format(Locale.US, "%.2f", it)
                    } ?: "—")
                    ReplayMetricRow("أطول سلسلة أرباح", report.longestWinStreak.toString())
                    ReplayMetricRow("أطول سلسلة خسائر", report.longestLossStreak.toString())
                    ReplayMetricRow("التراجع الحالي من القمة", String.format(Locale.US, "%.2f%%", report.currentDrawdownPercent))
                    ReplayMetricRow("أقصى تراجع بالقيمة", String.format(Locale.US, "%.2f USD", report.maxEquityDrawdownAmount))
                    ReplayMetricRow("الرابحة / الخاسرة", "$winners / $losers")
                    ReplayMetricRow("نسبة الفوز", String.format(Locale.US, "%.1f%%", winRate))
                    ReplayMetricRow("صافي الربح المحقق", String.format(Locale.US, "%+.2f USD", net))
                    ReplayMetricRow("إجمالي الأرباح", String.format(Locale.US, "%.2f USD", grossProfit))
                    ReplayMetricRow("إجمالي الخسائر", String.format(Locale.US, "%.2f USD", grossLoss))
                    ReplayMetricRow("معامل الربح", profitFactor?.let { String.format(Locale.US, "%.2f", it) }
                        ?: if (grossProfit > 0.0) "غير محدود (لا خسائر)" else "—")
                    HorizontalDivider()
                    ReplayMetricRow("الرصيد الحالي", String.format(Locale.US, "%.2f USD", uiState.currentBalance))
                    ReplayMetricRow("الملكية الحالية", String.format(Locale.US, "%.2f USD", uiState.currentEquity))
                    ReplayMetricRow("أعلى ملكية مسجلة", String.format(Locale.US, "%.2f USD", uiState.peakEquity))
                    ReplayMetricRow("أقصى تراجع من القمة", String.format(Locale.US, "%.2f%%", uiState.maxObservedDrawdownPercent))
                    ReplayMetricRow("نقاط منحنى الملكية", uiState.equitySamples.size.toString())
                    if (uiState.equitySamples.size >= 2) {
                        val first = uiState.equitySamples.first()
                        val last = uiState.equitySamples.last()
                        Text(
                            "تطور الملكية: " + String.format(Locale.US, "%.2f → %.2f USD", first.equity, last.equity),
                            fontSize = 12.sp,
                            color = TradingTextSecondary
                        )
                    }
                    ReplayMetricRow("العائد على الرصيد الابتدائي", String.format(Locale.US, "%+.2f%%", returnPercent))
                    ReplayMetricRow("الصفقات المفتوحة", uiState.openPositions.size.toString())
                    ReplayMetricRow("الأوامر المعلقة", uiState.pendingOrders.size.toString())
                }
            },
            confirmButton = {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    TextButton(
                        onClick = {
                            clipboardManager.setText(AnnotatedString(ReplayPerformanceAnalytics.exportSummaryCsv(report)))
                        },
                        modifier = Modifier.testTag("replay_export_summary_csv")
                    ) { Text("نسخ التقرير") }
                    TextButton(
                        enabled = uiState.closedTrades.isNotEmpty(),
                        onClick = {
                            clipboardManager.setText(AnnotatedString(ReplayPerformanceAnalytics.exportTradesCsv(uiState.closedTrades)))
                        },
                        modifier = Modifier.testTag("replay_export_trades_csv")
                    ) { Text("نسخ الصفقات") }
                    TextButton(
                        enabled = uiState.equitySamples.isNotEmpty(),
                        onClick = {
                            clipboardManager.setText(AnnotatedString(ReplayPerformanceAnalytics.exportEquityCsv(uiState.equitySamples)))
                        },
                        modifier = Modifier.testTag("replay_export_equity_csv")
                    ) { Text("نسخ المنحنى") }
                }
            },
            dismissButton = { TextButton(onClick = { showPerformanceDialog = false }) { Text("إغلاق") } }
        )
    }

    if (showIndicatorsDialog) {
        ChartIndicatorsDialog(
            currentSettings = indicatorSettings,
            onSaveSettings = { indicatorSettings = it; showIndicatorsDialog = false },
            onDismiss = { showIndicatorsDialog = false }
        )
    }

    editProtectionId?.let { positionId ->
        AlertDialog(
            onDismissRequest = { editProtectionId = null },
            title = { Text("تعديل حماية الصفقة #$positionId") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("اترك الحقل فارغًا لإزالة المستوى.", fontSize = 12.sp)
                    OutlinedTextField(
                        value = editSl,
                        onValueChange = { editSl = it },
                        label = { Text("وقف الخسارة SL") },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = editTp,
                        onValueChange = { editTp = it },
                        label = { Text("جني الأرباح TP") },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = (editSl.isBlank() || editSl.toDoubleOrNull()?.let { it.isFinite() && it > 0.0 } == true) &&
                        (editTp.isBlank() || editTp.toDoubleOrNull()?.let { it.isFinite() && it > 0.0 } == true),
                    onClick = {
                        viewModel.updatePositionProtection(
                            positionId,
                            editSl.takeIf { it.isNotBlank() }?.toDouble(),
                            editTp.takeIf { it.isNotBlank() }?.toDouble()
                        )
                        editProtectionId = null
                    }
                ) { Text("حفظ التعديل") }
            },
            dismissButton = { TextButton(onClick = { editProtectionId = null }) { Text("إلغاء") } }
        )
    }

    if (showOrderTicket) {
        AlertDialog(
            onDismissRequest = { showOrderTicket = false },
            title = { Text("أمر معلق — Replay") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(
                            selected = ticketSide == OrderSide.BUY,
                            onClick = { ticketSide = OrderSide.BUY; ticketType = OrderType.BUY_LIMIT },
                            label = { Text("شراء") }
                        )
                        FilterChip(
                            selected = ticketSide == OrderSide.SELL,
                            onClick = { ticketSide = OrderSide.SELL; ticketType = OrderType.SELL_LIMIT },
                            label = { Text("بيع") }
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(
                            selected = ticketType == OrderType.BUY_LIMIT || ticketType == OrderType.SELL_LIMIT,
                            onClick = { ticketType = if (ticketSide == OrderSide.BUY) OrderType.BUY_LIMIT else OrderType.SELL_LIMIT },
                            label = { Text("LIMIT") }
                        )
                        FilterChip(
                            selected = ticketType == OrderType.BUY_STOP || ticketType == OrderType.SELL_STOP,
                            onClick = { ticketType = if (ticketSide == OrderSide.BUY) OrderType.BUY_STOP else OrderType.SELL_STOP },
                            label = { Text("STOP") }
                        )
                    }
                    OutlinedTextField(value = ticketVolume, onValueChange = { ticketVolume = it }, label = { Text("حجم اللوت") }, singleLine = true)
                    OutlinedTextField(value = ticketPrice, onValueChange = { ticketPrice = it }, label = { Text("سعر التفعيل") }, singleLine = true)
                    OutlinedTextField(value = ticketSl, onValueChange = { ticketSl = it }, label = { Text("وقف الخسارة (اختياري)") }, singleLine = true)
                    OutlinedTextField(value = ticketTp, onValueChange = { ticketTp = it }, label = { Text("جني الأرباح (اختياري)") }, singleLine = true)
                }
            },
            confirmButton = {
                TextButton(
                    enabled = ticketVolume.toDoubleOrNull()?.let { it.isFinite() && it > 0 } == true &&
                        ticketPrice.toDoubleOrNull()?.let { it.isFinite() && it > 0 } == true &&
                        (ticketSl.isBlank() || ticketSl.toDoubleOrNull()?.let { it.isFinite() && it > 0 } == true) &&
                        (ticketTp.isBlank() || ticketTp.toDoubleOrNull()?.let { it.isFinite() && it > 0 } == true),
                    onClick = {
                        viewModel.placePendingOrder(
                            ticketType, ticketSide, ticketVolume.toDouble(),
                            ticketPrice.toDouble(), ticketSl.takeIf { it.isNotBlank() }?.toDouble(),
                            ticketTp.takeIf { it.isNotBlank() }?.toDouble()
                        )
                        showOrderTicket = false
                    }
                ) { Text("وضع الأمر") }
            },
            dismissButton = { TextButton(onClick = { showOrderTicket = false }) { Text("إلغاء") } }
        )
    }

    // Change instrument/timeframe without leaving the chart. Only instruments
    // backed by verified historical market data are offered for execution.
    if (showMarketDialog) {
        AlertDialog(
            onDismissRequest = { showMarketDialog = false },
            title = { Text("إعدادات سوق Replay") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("اختر الزوج", fontWeight = FontWeight.Bold)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("BTCUSDT", "ETHUSDT").forEach { symbol ->
                            FilterChip(
                                selected = uiState.symbol == symbol,
                                onClick = {
                                    showMarketDialog = false
                                    viewModel.loadReplayData(symbol, uiState.timeframe)
                                },
                                label = { Text(symbol) }
                            )
                        }
                    }
                    Text("الإطار الزمني", fontWeight = FontWeight.Bold)
                    Column(
                        modifier = Modifier.heightIn(max = 280.dp).verticalScroll(rememberScrollState())
                    ) {
                        Timeframe.entries.filter { it.minutes > 0 }.forEach { timeframe ->
                            Row(
                                modifier = Modifier.fillMaxWidth().clickable {
                                    showMarketDialog = false
                                    viewModel.loadReplayData(uiState.symbol, timeframe)
                                }.padding(vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                RadioButton(
                                    selected = uiState.timeframe == timeframe,
                                    onClick = {
                                        showMarketDialog = false
                                        viewModel.loadReplayData(uiState.symbol, timeframe)
                                    }
                                )
                                Spacer(Modifier.width(8.dp))
                                Text(timeframe.displayName)
                            }
                        }
                    }
                    Text("تغيير الزوج أو الإطار يعيد بدء الاختبار ويمسح صفقاته.", color = TradingTextSecondary, fontSize = 12.sp)
                }
            },
            confirmButton = { TextButton(onClick = { showMarketDialog = false }) { Text("إغلاق") } }
        )
    }

    // Verified historical range selection. Reloading starts a clean replay
    // account so old orders cannot contaminate a different dataset.
    if (showHistoryDialog) {
        AlertDialog(
            onDismissRequest = { showHistoryDialog = false },
            title = { Text("نطاق بيانات الباك تيست") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("اختر فترة تاريخية مكتملة من المصدر الحقيقي. تغيير الفترة أو النطاق يعيد ضبط جلسة Replay والصفقات.")
                    Text("نهاية الفترة التاريخية", fontWeight = FontWeight.Bold)
                    listOf(
                        0 to "أحدث البيانات",
                        300 to "قبل 300 شمعة",
                        1_000 to "قبل 1,000 شمعة",
                        3_000 to "قبل 3,000 شمعة"
                    ).forEach { (offset, label) ->
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable {
                                showHistoryDialog = false
                                viewModel.loadReplayData(uiState.symbol, uiState.timeframe, uiState.requestedHistoryBars, offset)
                            }.padding(vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(
                                selected = uiState.historyEndOffsetBars == offset,
                                onClick = {
                                    showHistoryDialog = false
                                    viewModel.loadReplayData(uiState.symbol, uiState.timeframe, uiState.requestedHistoryBars, offset)
                                }
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(label)
                        }
                    }
                    HorizontalDivider()
                    Text("عدد الشموع", fontWeight = FontWeight.Bold)
                    listOf(300, 1_000, 3_000, 5_000).forEach { count ->
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable {
                                showHistoryDialog = false
                                viewModel.loadReplayData(uiState.symbol, uiState.timeframe, count)
                            }.padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(
                                selected = uiState.requestedHistoryBars == count,
                                onClick = {
                                    showHistoryDialog = false
                                    viewModel.loadReplayData(uiState.symbol, uiState.timeframe, count)
                                }
                            )
                            Spacer(Modifier.width(8.dp))
                            Text("$count شمعة")
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showHistoryDialog = false }) { Text("إغلاق") } }
        )
    }

    // Jump to Date Dialog
    if (showJumpDialog) {
        AlertDialog(
            onDismissRequest = { showJumpDialog = false },
            title = { Text("القفز إلى موضع زمني") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(text = "اختر موضع القفز السريع في بيانات الشموع:", fontSize = 12.sp, color = TradingTextSecondary)
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                uiState.visibleCandles.firstOrNull()?.let { viewModel.jumpToTimestamp(it.openTime) }
                                showJumpDialog = false
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("أول شمعة ظاهرة")
                        }
                        Button(
                            onClick = {
                                val mid = uiState.visibleCandles.size / 2
                                uiState.visibleCandles.getOrNull(mid)?.let { viewModel.jumpToTimestamp(it.openTime) }
                                showJumpDialog = false
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("منتصف الظاهر")
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showJumpDialog = false }) { Text("إغلاق") }
            }
        )
    }
}

@Composable
private fun ReplayMetricRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, fontSize = 12.sp, color = TradingTextSecondary)
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}
