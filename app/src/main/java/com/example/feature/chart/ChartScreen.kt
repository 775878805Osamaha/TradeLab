package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.market.DefaultSymbols
import com.example.core.model.OrderSide
import com.example.core.model.Timeframe
import com.example.feature.chart.model.DrawingTool
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
    onNavigateToReplay: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    var showSymbolSheet by remember { mutableStateOf(false) }
    var showToolsMenu by remember { mutableStateOf(false) }
    var showIndicatorsDialog by remember { mutableStateOf(false) }
    var chartDisplayStyle by remember { mutableStateOf(ChartDisplayStyle.CANDLES) }

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
                            fontSize = 17.sp,
                            color = TradingTextPrimary
                        )
                        Icon(Icons.Default.ArrowDropDown, contentDescription = null, tint = TradingTextSecondary)
                        Spacer(modifier = Modifier.width(4.dp))
                        DataSourceBadge(sourceType = uiState.dataSourceType)
                    }
                },
                actions = {
                    // Replay shortcut
                    IconButton(
                        onClick = onNavigateToReplay,
                        modifier = Modifier.testTag("chart_to_replay_btn")
                    ) {
                        Icon(Icons.Default.PlayCircle, contentDescription = "إعادة العرض Replay", tint = TradingAccentLight)
                    }
                    // Crosshair toggle
                    IconButton(
                        onClick = { viewModel.toggleCrosshair() },
                        modifier = Modifier.testTag("chart_crosshair_btn")
                    ) {
                        Icon(
                            Icons.Default.FilterCenterFocus,
                            contentDescription = "التقاطع",
                            tint = if (uiState.isCrosshairActive) TradingAccent else TradingTextSecondary
                        )
                    }
                    // Indicators dialog button
                    IconButton(
                        onClick = { showIndicatorsDialog = true },
                        modifier = Modifier.testTag("chart_indicators_btn")
                    ) {
                        Icon(Icons.Default.Timeline, contentDescription = "المؤشرات الفنية", tint = TradingCyan)
                    }
                    // Drawings menu button
                    IconButton(
                        onClick = { showToolsMenu = !showToolsMenu },
                        modifier = Modifier.testTag("drawing_tools_menu_btn")
                    ) {
                        Icon(
                            Icons.Default.Draw,
                            contentDescription = "أدوات الرسم",
                            tint = if (uiState.activeDrawingTool != DrawingTool.NONE) TradingAccent else TradingTextSecondary
                        )
                    }
                    // Reset / Auto-fit view button
                    IconButton(
                        onClick = { viewModel.triggerResetView() },
                        modifier = Modifier.testTag("chart_reset_view_btn")
                    ) {
                        Icon(Icons.Default.CenterFocusWeak, contentDescription = "إعادة ضبط العرض", tint = TradingTextSecondary)
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
            // Timeframe selection scrollable row (all 10 timeframes)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 3.dp)
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
                            .padding(horizontal = 10.dp, vertical = 10.dp)
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

                // Chart rendering style selector (visual only; no impact on market data).
                ChartDisplayStyle.values().forEach { style ->
                    val selected = chartDisplayStyle == style
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (selected) TradingAccent else TradingElevated)
                            .clickable { chartDisplayStyle = style }
                            .padding(horizontal = 8.dp, vertical = 5.dp)
                            .testTag("chart_style_${style.name}")
                    ) {
                        Text(style.label, fontSize = 10.sp,
                            color = if (selected) Color.White else TradingTextSecondary)
                    }
                }

                // Volume toggle chip
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(if (uiState.isVolumeVisible) TradingGold.copy(alpha = 0.2f) else TradingElevated)
                        .clickable { viewModel.toggleVolume() }
                        .padding(horizontal = 7.dp, vertical = 5.dp)
                ) {
                    Text(
                        text = "VOL",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (uiState.isVolumeVisible) TradingGold else TradingTextSecondary
                    )
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
                System.currentTimeMillis() - marketTick.timestamp in 0..15_000L
            val verifiedBinancePair = uiState.selectedSymbol in setOf("BTCUSDT", "ETHUSDT")
            val marketStatus = when {
                !verifiedBinancePair -> "لا يوجد مصدر أسعار مباشر معتمد لهذا الرمز"
                !marketTickIsLive -> "بانتظار سعر حديث من Binance"
                marketTick?.source == "BINANCE_WEBSOCKET" -> "Binance · بث مباشر"
                else -> "Binance · تحديث عبر الإنترنت"
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 5.dp),
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

            // Professional Candlestick Chart
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                CandlestickChart(
                    candles = uiState.candles,
                    latestTick = uiState.latestTick,
                    openPositions = uiState.openPositions,
                    pendingOrders = uiState.pendingOrders,
                    historicalTrades = uiState.historicalTrades,
                    activeDrawingTool = uiState.activeDrawingTool,
                    drawings = uiState.drawings,
                    indicatorSettings = uiState.indicatorSettings,
                    smaValues = uiState.smaValues,
                    emaValues = uiState.emaValues,
                    bollingerValues = uiState.bollingerValues,
                    vwapValues = uiState.vwapValues,
                    rsiValues = uiState.rsiValues,
                    macdValues = uiState.macdValues,
                    atrValues = uiState.atrValues,
                    isCrosshairActive = uiState.isCrosshairActive,
                    isVolumeVisible = uiState.isVolumeVisible,
                    resetViewTrigger = uiState.resetViewTrigger,
                    displayStyle = chartDisplayStyle,
                    onAddDrawing = { viewModel.addDrawing(it) },
                    onSelectTrade = { viewModel.selectTradeForDetail(it) }
                )

                // Compact TradingView-style tools on the chart itself.
                // Buttons select the existing functional drawing tools; no image overlay.
                Surface(
                    modifier = Modifier
                        .align(Alignment.CenterEnd)
                        .padding(horizontal = 5.dp)
                        .testTag("chart_floating_drawing_toolbar"),
                    shape = RoundedCornerShape(8.dp),
                    color = TradingCard.copy(alpha = 0.96f),
                    border = androidx.compose.foundation.BorderStroke(1.dp, TradingBorder),
                    tonalElevation = 0.dp
                ) {
                    Column(
                        modifier = Modifier.padding(vertical = 4.dp),
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
                                modifier = Modifier.size(44.dp).testTag("chart_toolbar_${tool.name}")
                            ) {
                                Icon(
                                    imageVector = icon,
                                    contentDescription = description,
                                    tint = if (selected) TradingAccent else TradingTextSecondary,
                                    modifier = Modifier.size(21.dp)
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
                            onClick = { showToolsMenu = true },
                            modifier = Modifier.size(44.dp).testTag("chart_toolbar_more")
                        ) {
                            Icon(Icons.Default.MoreHoriz, contentDescription = "المزيد من أدوات الرسم", tint = TradingTextSecondary)
                        }
                    }
                }
            }

            // Quick Execution Bar
            Surface(
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
                        onClick = { viewModel.quickOrder(OrderSide.SELL, 0.01) },
                        modifier = Modifier
                            .weight(1f)
                            .height(46.dp)
                            .testTag("chart_quick_sell_btn"),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingNegative)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("بيع (SELL)", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Text(bidText, fontSize = 11.sp)
                        }
                    }

                    // Spread / Info Chip
                    val spreadText = (if (marketTickIsLive) marketTick else null)?.let {
                        val sym = DefaultSymbols.getSymbol(uiState.selectedSymbol)
                        String.format(Locale.US, "%.1f", it.spread / sym.pipSize)
                    } ?: "--"
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(text = "السبريد", fontSize = 10.sp, color = TradingTextSecondary)
                        Text(text = "$spreadText pips", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TradingTextPrimary)
                    }

                    // BUY Button (Green)
                    val askText = if (marketTickIsLive) marketTick?.let { String.format(Locale.US, "%.2f", it.ask) } ?: "--" else "--"
                    Button(
                        onClick = { viewModel.quickOrder(OrderSide.BUY, 0.01) },
                        modifier = Modifier
                            .weight(1f)
                            .height(46.dp)
                            .testTag("chart_quick_buy_btn"),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingPositive)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("شراء (BUY)", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Text(askText, fontSize = 11.sp)
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
                            Text(text = sym.symbol, fontWeight = FontWeight.Bold, fontSize = 15.sp)
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
