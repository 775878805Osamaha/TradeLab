package com.example.feature.results

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
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
import com.example.core.model.ExitReason
import com.example.core.model.PositionSide
import com.example.ui.components.ChartCurveType
import com.example.ui.components.EquityCurveChart
import com.example.ui.components.StatTile
import com.example.ui.theme.*
import java.util.Locale
import java.text.SimpleDateFormat
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ResultsScreen(
    viewModel: ResultsViewModel,
    onNavigateToHistory: () -> Unit,
    onNavigateToBacktest: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val metrics = uiState.metrics

    // Dialogs
    uiState.selectedTradeForDetail?.let { trade ->
        TradeDetailDialog(trade = trade, onDismiss = { viewModel.selectTradeForDetail(null) })
    }

    if (uiState.isExportDialogOpen && metrics != null) {
        // Export exactly the period shown on the overview; other tabs retain
        // their existing full-account export behavior.
        val periodReport = remember(uiState.trades, uiState.initialBalance, uiState.selectedPeriod, uiState.selectedTab) {
            if (uiState.selectedTab == ResultsTab.OVERVIEW) {
                ResultsPeriodCalculator.calculate(
                    uiState.initialBalance, uiState.trades,
                    uiState.selectedPeriod, System.currentTimeMillis()
                )
            } else null
        }
        val exportedTrades = periodReport?.trades ?: uiState.trades
        ExportDialog(
            metrics = periodReport?.metrics ?: metrics,
            trades = exportedTrades,
            dailySummaries = if (periodReport != null) {
                com.example.core.statistics.StatisticsCalculator.calculateDailySummaries(exportedTrades)
            } else uiState.dailySummaries,
            points = periodReport?.curve ?: uiState.equityPoints,
            onDismiss = { viewModel.setExportDialogOpen(false) }
        )
    }

    Scaffold(
        modifier = modifier.testTag("results_screen"),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "النتائج",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold
                    )
                },
                actions = {


                    IconButton(
                        onClick = { viewModel.setExportDialogOpen(true) },
                        modifier = Modifier.testTag("export_results_btn")
                    ) {
                        Icon(Icons.Default.FileDownload, contentDescription = "تصدير النتائج", tint = TradingAccent)
                    }
                    IconButton(
                        onClick = onNavigateToHistory,
                        modifier = Modifier.testTag("results_to_history_btn")
                    ) {
                        Icon(Icons.Default.History, contentDescription = "سجل الصفقات")
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
            Column(Modifier.fillMaxWidth().background(ResultsCardBackground).padding(horizontal=12.dp,vertical=8.dp).testTag("results_positions_summary")) {
                Text("حساب التدريب · ${uiState.openPositionsCount} مفتوحة · ${uiState.trades.size} مغلقة",color=ResultsText,fontSize=12.sp)
                Text("الربح العائم: ${money(uiState.openPositions.sumOf { it.profitLoss },true)} · الربح المحقق: ${money(uiState.trades.sumOf { it.netProfitLoss },true)}",color=ResultsMuted,fontSize=11.sp)
                uiState.openPositions.take(2).forEach { position ->
                    Text("${position.symbol} · ${position.side} · ${position.volume} لوت · ${money(position.profitLoss,true)}",color=ResultsProfit,fontSize=11.sp)
                }
            }
            // Main Results Tabs
            ScrollableTabRow(
                selectedTabIndex = uiState.selectedTab.ordinal,
                edgePadding = 8.dp,
                containerColor = TradingCard,
                contentColor = TradingAccent,
                modifier = Modifier.fillMaxWidth()
            ) {
                ResultsTab.values().filter { it != ResultsTab.COMPARISON }.forEach { tab ->
                    Tab(
                        selected = uiState.selectedTab == tab,
                        onClick = { viewModel.setSelectedTab(tab) },
                        text = {
                            Text(
                                text = tab.displayNameAr,
                                maxLines = 1,
                                softWrap = false,
                                fontSize = 12.sp,
                                fontWeight = if (uiState.selectedTab == tab) FontWeight.Bold else FontWeight.Normal
                            )
                        }
                    )
                }
            }

            when (uiState.selectedTab) {
                ResultsTab.OVERVIEW -> ResultsOverviewContent(viewModel, uiState, onNavigateToBacktest)
                ResultsTab.CURVES -> ResultsCurvesContent(viewModel, uiState)
                ResultsTab.JOURNAL -> ResultsJournalContent(viewModel, uiState)
                ResultsTab.DAILY -> ResultsDailyContent(viewModel, uiState)
                ResultsTab.COMPARISON -> ResultsComparisonContent(viewModel, uiState)
            }
        }
    }
}


private val ResultsCardBackground = Color(0xFF131A24)
private val ResultsCardBorder = Color(0xFF232C3A)
private val ResultsPrimary = Color(0xFF2962FF)
private val ResultsProfit = Color(0xFF26D9B0)
private val ResultsLoss = Color(0xFFEF5350)
private val ResultsText = Color(0xFFE8ECF4)
private val ResultsMuted = Color(0xFF8F98A8)

private fun money(value: Double, signed: Boolean = false): String {
    if (!value.isFinite()) return "—"
    return String.format(Locale.US, "%s$%,.2f", if (signed && value > 0) "+" else "", value)
}

private fun percent(value: Double, signed: Boolean = false): String {
    if (!value.isFinite()) return "—"
    return String.format(Locale.US, "%s%.2f%%", if (signed && value > 0) "+" else "", value)
}

@Composable
private fun ResultsMetricCard(
    title: String,
    value: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconColor: Color,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    valueColor: Color = ResultsText,
    progress: Float? = null
) {
    Card(
        modifier = modifier.heightIn(min = 104.dp),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = ResultsCardBackground),
        border = androidx.compose.foundation.BorderStroke(1.dp, ResultsCardBorder)
    ) {
        Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(title, fontSize = 11.sp, color = ResultsMuted, maxLines = 1)
                Box(Modifier.size(32.dp).clip(RoundedCornerShape(9.dp)).background(iconColor.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
                    Icon(icon, null, tint = iconColor, modifier = Modifier.size(19.dp))
                }
            }
            Text(value, fontSize = 21.sp, fontWeight = FontWeight.Bold, color = valueColor, maxLines = 1,
                style = TextStyle(textDirection = TextDirection.Ltr))
            if (progress != null) {
                LinearProgressIndicator(
                    progress = { progress.coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().height(5.dp).clip(RoundedCornerShape(3.dp)),
                    color = ResultsProfit, trackColor = ResultsCardBorder
                )
            }
            if (subtitle != null) Text(subtitle, fontSize = 10.sp, color = ResultsMuted, maxLines = 2)
        }
    }
}

@Composable
private fun ResultsOverviewContent(
    viewModel: ResultsViewModel,
    uiState: ResultsUiState,
    onNavigateToBacktest: () -> Unit
) {
    val period = uiState.selectedPeriod
    val now = remember { System.currentTimeMillis() }
    val snapshot = remember(uiState.trades, uiState.initialBalance,uiState.metrics,uiState.equityPoints, period, now) {
        ResultsPeriodCalculator.calculate(uiState.initialBalance, uiState.trades, period, now).let { if(period==ResultsPeriod.ALL && uiState.metrics!=null) it.copy(metrics=uiState.metrics,curve=uiState.equityPoints) else it }
    }
    val metrics = snapshot.metrics
    val trades = snapshot.trades
    val net = metrics.netProfit
    val pnlColor = when {
        net > 0.0 -> ResultsProfit
        net < 0.0 -> ResultsLoss
        else -> ResultsMuted
    }
    val recent = remember(trades) { trades.sortedByDescending { it.closeTime }.take(3) }
    val dateFormat = remember { SimpleDateFormat("dd/MM HH:mm", Locale.US) }

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(Color(0xFF0B0E14)),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 28.dp)
    ) {
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Surface(color = ResultsCardBackground, shape = RoundedCornerShape(10.dp),
                    border = androidx.compose.foundation.BorderStroke(1.dp, ResultsCardBorder)) {
                    Row(Modifier.padding(horizontal = 12.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.CalendarMonth, null, tint = ResultsMuted, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(when(period) { ResultsPeriod.MONTH -> "هذا الشهر"; ResultsPeriod.WEEK -> "هذا الأسبوع"; ResultsPeriod.ALL -> "كل الفترات" },
                            color = ResultsText, fontSize = 12.sp)
                    }
                }
                Row(Modifier.clip(RoundedCornerShape(10.dp)).background(ResultsCardBackground).padding(4.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    listOf(ResultsPeriod.ALL, ResultsPeriod.MONTH, ResultsPeriod.WEEK).forEach { item ->
                        Box(
                            Modifier.clip(RoundedCornerShape(8.dp))
                                .background(if (period == item) ResultsPrimary else Color.Transparent)
                                .clickable { viewModel.setSelectedPeriod(item) }
                                .padding(horizontal = 16.dp, vertical = 8.dp)
                                .testTag("results_period_${item.name}"),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(item.titleAr, fontSize = 12.sp, color = if (period == item) Color.White else ResultsMuted)
                        }
                    }
                }
            }
        }

        item {
            Card(
                modifier = Modifier.fillMaxWidth().testTag("results_hero_card"),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = ResultsCardBackground),
                border = androidx.compose.foundation.BorderStroke(1.dp, ResultsCardBorder)
            ) {
                Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Top) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("صافي الربح التراكمي", color = ResultsText, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.width(6.dp))
                            Icon(Icons.Default.Info, null, tint = ResultsMuted, modifier = Modifier.size(16.dp))
                        }
                        Surface(color = pnlColor.copy(alpha = 0.16f), shape = RoundedCornerShape(8.dp)) {
                            Text(percent(metrics.returnPct, true), modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
                                color = pnlColor, fontSize = 15.sp, fontWeight = FontWeight.Bold,
                                style = TextStyle(textDirection = TextDirection.Ltr))
                        }
                    }
                    Text(
                        if (uiState.isPercentageMode) percent(metrics.returnPct, true) else money(net, true),
                        fontSize = 33.sp, fontWeight = FontWeight.Bold, color = pnlColor, maxLines = 1,
                        style = TextStyle(textDirection = TextDirection.Ltr),
                        modifier = Modifier.align(Alignment.CenterHorizontally)
                    )
                    Text("الرصيد: ${money(snapshot.closingBalance)}", color = ResultsMuted, fontSize = 13.sp,
                        modifier = Modifier.align(Alignment.CenterHorizontally))
                    Surface(
                        modifier = Modifier.clickable { viewModel.togglePercentageMode() }.testTag("results_percentage_toggle"),
                        color = Color(0xFF101D2D), shape = RoundedCornerShape(8.dp),
                        border = androidx.compose.foundation.BorderStroke(1.dp, ResultsCardBorder)
                    ) {
                        Text(if (uiState.isPercentageMode) "عرض القيمة ($)" else "عرض النسبة (%)",
                            Modifier.padding(horizontal = 12.dp, vertical = 7.dp), fontSize = 11.sp, color = ResultsText)
                    }
                    if (trades.isEmpty()) {
                        Column(Modifier.fillMaxWidth().height(110.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center) {
                            Text("لا توجد صفقات مغلقة بعد", color = ResultsMuted, fontSize = 13.sp)
                            Spacer(Modifier.height(12.dp))
                            Button(
                                onClick = onNavigateToBacktest,
                                colors = ButtonDefaults.buttonColors(containerColor = ResultsPrimary),
                                modifier = Modifier.testTag("results_start_backtest")
                            ) { Text("ابدأ التداول على الشارت", color = Color.White) }
                        }
                    } else {
                        EquityCurveChart(
                            points = snapshot.curve,
                            initialBalance = snapshot.openingBalance,
                            isPercentageMode = uiState.isPercentageMode,
                            curveType = ChartCurveType.EQUITY_AND_BALANCE
                        )
                    }
                }
            }
        }

        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ResultsMetricCard("عامل الربح", metrics.profitFactor?.let { String.format(Locale.US, "%.2f", it) } ?: "—",
                    Icons.Default.Layers, ResultsPrimary, Modifier.weight(1f))
                ResultsMetricCard("معدل الفوز", if (metrics.totalTrades > 0) percent(metrics.winRatePct) else "—",
                    Icons.Default.TrackChanges, ResultsProfit, Modifier.weight(1f),
                    subtitle = "${metrics.winningTrades} رابحة / ${metrics.losingTrades} خاسرة",
                    progress = if (metrics.totalTrades > 0) (metrics.winRatePct / 100.0).toFloat() else 0f)
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ResultsMetricCard("إجمالي الصفقات", "${metrics.totalTrades}", Icons.Default.BarChart, ResultsPrimary,
                    Modifier.weight(1f), subtitle = "${metrics.winningTrades} رابحة / ${metrics.losingTrades} خاسرة")
                ResultsMetricCard("أقصى تراجع", percent(metrics.maxDrawdownPct),
                    Icons.Default.TrendingDown, ResultsLoss, Modifier.weight(1f),
                    subtitle = money(metrics.maxDrawdown), valueColor = ResultsLoss)
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ResultsMetricCard("التوقع الرياضي", metrics.expectancy?.let { money(it, true) } ?: "—",
                    Icons.Default.Functions, ResultsProfit, Modifier.weight(1f), subtitle = "لكل صفقة",
                    valueColor = if ((metrics.expectancy ?: 0.0) >= 0) ResultsProfit else ResultsLoss)
                ResultsMetricCard("نسبة شارب", metrics.sharpeRatio?.let { String.format(Locale.US, "%.2f", it) } ?: "—",
                    Icons.Default.ShowChart, ResultsPrimary, Modifier.weight(1f))
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ResultsMetricCard("متوسط الخسارة", metrics.avgLoss?.let { money(-kotlin.math.abs(it)) } ?: "—",
                    Icons.Default.South, ResultsLoss, Modifier.weight(1f), valueColor = ResultsLoss)
                ResultsMetricCard("متوسط الربح", metrics.avgWin?.let { money(it, true) } ?: "—",
                    Icons.Default.North, ResultsProfit, Modifier.weight(1f), valueColor = ResultsProfit)
            }
        }

        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = ResultsCardBackground),
                border = androidx.compose.foundation.BorderStroke(1.dp, ResultsCardBorder)
            ) {
                Column(Modifier.fillMaxWidth().padding(12.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically) {
                        Text("أحدث الصفقات", fontSize = 14.sp, color = ResultsText, fontWeight = FontWeight.Bold)
                        Text("عرض الكل", fontSize = 12.sp, color = ResultsPrimary,
                            modifier = Modifier.clickable { viewModel.setSelectedTab(ResultsTab.JOURNAL) })
                    }
                    Spacer(Modifier.height(7.dp))
                    if (recent.isEmpty()) {
                        Text("لا توجد صفقات خلال هذه الفترة", color = ResultsMuted, fontSize = 12.sp,
                            modifier = Modifier.padding(vertical = 16.dp))
                    }
                    recent.forEach { trade ->
                        HorizontalDivider(color = ResultsCardBorder)
                        Row(Modifier.fillMaxWidth().clickable { viewModel.selectTradeForDetail(trade) }
                            .padding(vertical = 11.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                            Surface(color = (if (trade.side == PositionSide.BUY) ResultsProfit else ResultsLoss).copy(alpha = 0.16f),
                                shape = RoundedCornerShape(6.dp)) {
                                Text(if (trade.side == PositionSide.BUY) "شراء" else "بيع",
                                    Modifier.padding(horizontal = 9.dp, vertical = 5.dp),
                                    color = if (trade.side == PositionSide.BUY) ResultsProfit else ResultsLoss, fontSize = 11.sp)
                            }
                            Text(trade.symbol, color = ResultsText, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.weight(1f), maxLines = 1)
                            Text(dateFormat.format(Date(trade.closeTime)), color = ResultsMuted, fontSize = 10.sp, maxLines = 1)
                            Text(money(trade.netProfitLoss, true),
                                color = if (trade.netProfitLoss >= 0) ResultsProfit else ResultsLoss,
                                fontWeight = FontWeight.Bold, fontSize = 12.sp,
                                style = TextStyle(textDirection = TextDirection.Ltr), maxLines = 1)
                            Icon(Icons.Default.ChevronLeft, null, tint = ResultsMuted, modifier = Modifier.size(17.dp))
                        }
                    }
                }
            }
        }

        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = ResultsCardBackground),
                border = androidx.compose.foundation.BorderStroke(1.dp, ResultsCardBorder)
            ) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("إحصاءات التداول والمخاطر التفصيلية", color = ResultsText, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    HorizontalDivider(color = ResultsCardBorder)
                    MetricRow("أقصى تتابع رابح", "${metrics.maxConsecutiveWins}")
                    MetricRow("أقصى تتابع خاسر", "${metrics.maxConsecutiveLosses}")
                    MetricRow("أفضل صفقة", metrics.bestTrade?.let { money(it, true) } ?: "—")
                    MetricRow("أسوأ صفقة", metrics.worstTrade?.let { money(it) } ?: "—")
                    MetricRow("متوسط مدة الصفقة", "${metrics.avgDurationMillis / 60_000} دقيقة")
                    MetricRow("إجمالي حجم العقود", String.format(Locale.US, "%.2f Lot", metrics.totalVolume))
                    MetricRow("متوسط المضاعف R", metrics.avgRMultiple?.let { String.format(Locale.US, "%.2f R", it) } ?: "—")
                    MetricRow("نسبة سورتينو", metrics.sortinoRatio?.let { String.format(Locale.US, "%.2f", it) } ?: "—")
                    MetricRow("عامل التعافي", metrics.recoveryFactor?.let { String.format(Locale.US, "%.2f", it) } ?: "—")
                }
            }
        }
    }
}

@Composable
private fun ResultsCurvesContent(
    viewModel: ResultsViewModel,
    uiState: ResultsUiState
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Curve Type Selectors & Value/Percentage Toggle
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Curve type row
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ChartCurveType.values().forEach { type ->
                        val isSel = uiState.curveType == type
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(if (isSel) TradingAccent else TradingElevated)
                                .clickable { viewModel.setCurveType(type) }
                                .padding(horizontal = 8.dp, vertical = 5.dp)
                        ) {
                            Text(
                                text = type.displayNameAr,
                                fontSize = 11.sp,
                                fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal,
                                color = if (isSel) Color.White else TradingTextSecondary
                            )
                        }
                    }
                }

                // Value vs Pct
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(TradingElevated)
                        .clickable { viewModel.togglePercentageMode() }
                        .padding(horizontal = 8.dp, vertical = 5.dp)
                ) {
                    Text(
                        text = if (uiState.isPercentageMode) "%" else "$",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = TradingCyan
                    )
                }
            }
        }

        // Interactive Chart Canvas
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(
                        text = "${uiState.curveType.displayNameAr} (${if (uiState.isPercentageMode) "نسبة مئوية %" else "قيمة مالية $"})",
                        fontSize = 12.sp,
                        color = TradingTextSecondary
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    EquityCurveChart(
                        points = uiState.equityPoints,
                        initialBalance = uiState.initialBalance,
                        isPercentageMode = uiState.isPercentageMode,
                        curveType = uiState.curveType
                    )
                }
            }
        }

        item {
            Text(
                text = "المس أو اسحب على الرسم البياني لعرض خط التقاطع (Crosshair) وتفاصيل الرصيد والتراجع عند أي نقطة زمنية.",
                fontSize = 11.sp,
                color = TradingTextMuted,
                lineHeight = 16.sp
            )
        }
    }
}

@Composable
private fun ResultsJournalContent(
    viewModel: ResultsViewModel,
    uiState: ResultsUiState
) {
    var selectedFilter by remember { mutableStateOf("ALL") }

    val filtered = remember(uiState.trades, selectedFilter) {
        uiState.trades.filter { t ->
            when (selectedFilter) {
                "WIN" -> t.netProfitLoss > 0
                "LOSS" -> t.netProfitLoss < 0
                "BUY" -> t.side == PositionSide.BUY
                "SELL" -> t.side == PositionSide.SELL
                "SL" -> t.exitReason == ExitReason.STOP_LOSS
                "TP" -> t.exitReason == ExitReason.TAKE_PROFIT
                else -> true
            }
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
    ) {
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val filters = listOf(
                    "ALL" to "الكل (${uiState.trades.size})",
                    "WIN" to "رابحة",
                    "LOSS" to "خاسرة",
                    "BUY" to "شراء",
                    "SELL" to "بيع",
                    "SL" to "ضرب SL",
                    "TP" to "تحقيق TP"
                )
                items(filters) { (key, label) ->
                    val isSel = selectedFilter == key
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (isSel) TradingAccent else TradingElevated)
                            .clickable { selectedFilter = key }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
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
        }

        if (filtered.isEmpty()) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text("لا توجد صفقات مطابقة للفلتر المحدد", color = TradingTextSecondary, fontSize = 12.sp)
                }
            }
        } else {
            items(filtered, key = { it.id }) { trade ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.selectTradeForDetail(trade) },
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(4.dp))
                                    .background(if (trade.side == PositionSide.BUY) TradingPositive.copy(alpha = 0.2f) else TradingNegative.copy(alpha = 0.2f))
                                    .padding(horizontal = 6.dp, vertical = 3.dp)
                            ) {
                                Text(
                                    text = if (trade.side == PositionSide.BUY) "BUY" else "SELL",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (trade.side == PositionSide.BUY) TradingPositive else TradingNegative
                                )
                            }
                            Spacer(modifier = Modifier.width(8.dp))
                            Column {
                                Text(text = "${trade.symbol} • ${trade.volume} Lot", fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                Text(
                                    text = "${trade.entryPrice} -> ${trade.exitPrice} • R: ${String.format(Locale.US, "%.1f", trade.rMultiple)}",
                                    fontSize = 11.sp,
                                    color = TradingTextSecondary
                                )
                            }
                        }

                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                text = String.format(Locale.US, "%s$%.2f", if (trade.netProfitLoss >= 0) "+" else "", trade.netProfitLoss),
                                fontWeight = FontWeight.Bold,
                                fontSize = 13.sp,
                                color = if (trade.netProfitLoss >= 0) TradingPositive else TradingNegative
                            )
                            Text(text = trade.exitReason.name, fontSize = 10.sp, color = TradingTextMuted)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ResultsDailyContent(
    viewModel: ResultsViewModel,
    uiState: ResultsUiState
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
    ) {
        item {
            Text(
                text = "سجل الإغلاقات اليومية المجمعة (${uiState.dailySummaries.size} يوم تداول)",
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp
            )
        }

        if (uiState.dailySummaries.isEmpty()) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text("لا توجد أيام تداول مسجلة بعد", color = TradingTextSecondary, fontSize = 12.sp)
                }
            }
        } else {
            items(uiState.dailySummaries, key = { it.fullDate }) { d ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(text = d.fullDate, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                            Text(
                                text = "${d.tradeCount} صفقات • حجم: ${String.format(Locale.US, "%.2f", d.totalLots)} Lot • فوز: ${String.format(Locale.US, "%.0f%%", d.winRatePct)}",
                                fontSize = 11.sp,
                                color = TradingTextSecondary
                            )
                        }
                        Text(
                            text = String.format(Locale.US, "%s$%.2f", if (d.profitLoss >= 0) "+" else "", d.profitLoss),
                            fontWeight = FontWeight.Bold,
                            fontSize = 14.sp,
                            color = if (d.profitLoss >= 0) TradingPositive else TradingNegative
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ResultsComparisonContent(
    viewModel: ResultsViewModel,
    uiState: ResultsUiState
) {
    val selectedRuns = uiState.pastRuns.filter { it.id in uiState.selectedRunsForComparison }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
    ) {
        item {
            Text(
                text = "حدد اختبارين أو أكثر للمقارنة المحايدة جنباً إلى جنب:",
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp
            )
        }

        if (uiState.pastRuns.isEmpty()) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text("لا توجد اختبارات محفوظة في قاعدة البيانات للمقارنة", color = TradingTextSecondary, fontSize = 12.sp)
                }
            }
        } else {
            items(uiState.pastRuns, key = { it.id }) { run ->
                val isSelected = run.id in uiState.selectedRunsForComparison
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.toggleRunComparison(run.id) },
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(containerColor = if (isSelected) TradingElevated else TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(
                        brush = androidx.compose.ui.graphics.SolidColor(if (isSelected) TradingAccent else TradingBorder)
                    )
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(
                                checked = isSelected,
                                onCheckedChange = { viewModel.toggleRunComparison(run.id) }
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Column {
                                Text(text = run.strategyName, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                Text(text = "${run.symbol} • ${run.timeframe.displayName} • ${run.totalTrades} صفقة", fontSize = 11.sp, color = TradingTextSecondary)
                            }
                        }

                        Text(
                            text = String.format(Locale.US, "%s$%.2f", if (run.netProfit >= 0) "+" else "", run.netProfit),
                            fontWeight = FontWeight.Bold,
                            fontSize = 13.sp,
                            color = if (run.netProfit >= 0) TradingPositive else TradingNegative
                        )
                    }
                }
            }

            if (selectedRuns.size >= 2) {
                item {
                    var showModal by remember { mutableStateOf(false) }
                    if (showModal) {
                        RunComparisonDialog(runs = selectedRuns, onDismiss = { showModal = false })
                    }

                    Button(
                        onClick = { showModal = true },
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingAccent)
                    ) {
                        Icon(Icons.Default.CompareArrows, contentDescription = null)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("عرض جدول المقارنة التفصيلي (${selectedRuns.size})", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
private fun MetricRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = label, fontSize = 12.sp, color = TradingTextSecondary)
        Text(text = value, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = TradingTextPrimary)
    }
}
