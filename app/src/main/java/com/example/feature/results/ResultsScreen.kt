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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.model.ExitReason
import com.example.core.model.PositionSide
import com.example.ui.components.ChartCurveType
import com.example.ui.components.EquityCurveChart
import com.example.ui.components.StatTile
import com.example.ui.theme.*
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ResultsScreen(
    viewModel: ResultsViewModel,
    onNavigateToHistory: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val metrics = uiState.metrics

    // Dialogs
    uiState.selectedTradeForDetail?.let { trade ->
        TradeDetailDialog(trade = trade, onDismiss = { viewModel.selectTradeForDetail(null) })
    }

    if (uiState.isExportDialogOpen && metrics != null) {
        ExportDialog(
            metrics = metrics,
            trades = uiState.trades,
            dailySummaries = uiState.dailySummaries,
            points = uiState.equityPoints,
            onDismiss = { viewModel.setExportDialogOpen(false) }
        )
    }

    Scaffold(
        modifier = modifier.testTag("results_screen"),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "لوحة التحليلات والنتائج",
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
            // Main Results Tabs
            TabRow(
                selectedTabIndex = uiState.selectedTab.ordinal,
                containerColor = TradingCard,
                contentColor = TradingAccent,
                modifier = Modifier.fillMaxWidth()
            ) {
                ResultsTab.values().forEach { tab ->
                    Tab(
                        selected = uiState.selectedTab == tab,
                        onClick = { viewModel.setSelectedTab(tab) },
                        text = {
                            Text(
                                text = tab.displayNameAr,
                                fontSize = 11.sp,
                                fontWeight = if (uiState.selectedTab == tab) FontWeight.Bold else FontWeight.Normal
                            )
                        }
                    )
                }
            }

            when (uiState.selectedTab) {
                ResultsTab.OVERVIEW -> ResultsOverviewContent(viewModel, uiState)
                ResultsTab.CURVES -> ResultsCurvesContent(viewModel, uiState)
                ResultsTab.JOURNAL -> ResultsJournalContent(viewModel, uiState)
                ResultsTab.DAILY -> ResultsDailyContent(viewModel, uiState)
                ResultsTab.COMPARISON -> ResultsComparisonContent(viewModel, uiState)
            }
        }
    }
}

@Composable
private fun ResultsOverviewContent(
    viewModel: ResultsViewModel,
    uiState: ResultsUiState
) {
    val metrics = uiState.metrics

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 28.dp)
    ) {
        // Hero Return Card
        item {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("results_hero_card"),
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = "صافي الربح التراكمي", fontSize = 12.sp, color = TradingTextSecondary)
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(TradingElevated)
                                .clickable { viewModel.togglePercentageMode() }
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        ) {
                            Text(
                                text = if (uiState.isPercentageMode) "عرض القيمة ($)" else "عرض النسبة (%)",
                                fontSize = 11.sp,
                                color = TradingCyan,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(4.dp))

                    val netProfit = metrics?.netProfit ?: 0.0
                    val returnPct = metrics?.returnPct ?: 0.0
                    val isPos = netProfit >= 0.0

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.Bottom
                    ) {
                        Text(
                            text = if (uiState.isPercentageMode) {
                                String.format(Locale.US, "%s%.2f%%", if (returnPct >= 0) "+" else "", returnPct)
                            } else {
                                String.format(Locale.US, "%s$%.2f", if (isPos) "+" else "", netProfit)
                            },
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isPos) TradingPositive else TradingNegative
                        )
                        Text(
                            text = String.format(Locale.US, "الرصيد: $%.2f", uiState.currentBalance),
                            fontSize = 13.sp,
                            color = TradingTextSecondary
                        )
                    }
                }
            }
        }

        // Primary Metrics Grid
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTile(
                    label = "عامل الربح (PF)",
                    value = metrics?.profitFactor?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A",
                    modifier = Modifier.weight(1f)
                )
                StatTile(
                    label = "معدل الفوز (Win Rate)",
                    value = if (metrics != null && metrics.totalTrades > 0) String.format(Locale.US, "%.1f%%", metrics.winRatePct) else "N/A",
                    isPositive = (metrics?.winRatePct ?: 0.0) >= 50.0,
                    modifier = Modifier.weight(1f)
                )
            }
        }

        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTile(
                    label = "أقصى تراجع (Drawdown)",
                    value = metrics?.let { String.format(Locale.US, "%.1f%% ($%.2f)", it.maxDrawdownPct, it.maxDrawdown) } ?: "N/A",
                    isPositive = false,
                    modifier = Modifier.weight(1f)
                )
                StatTile(
                    label = "التوقع الرياضي (Expectancy)",
                    value = metrics?.expectancy?.let { String.format(Locale.US, "$%.2f", it) } ?: "N/A",
                    isPositive = (metrics?.expectancy ?: 0.0) >= 0.0,
                    modifier = Modifier.weight(1f)
                )
            }
        }

        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTile(
                    label = "نسبة شارب (Sharpe)",
                    value = metrics?.sharpeRatio?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A",
                    modifier = Modifier.weight(1f)
                )
                StatTile(
                    label = "نسبة سورتينو (Sortino)",
                    value = metrics?.sortinoRatio?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A",
                    modifier = Modifier.weight(1f)
                )
            }
        }

        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTile(
                    label = "عامل التعافي (Recovery)",
                    value = metrics?.recoveryFactor?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A",
                    modifier = Modifier.weight(1f)
                )
                StatTile(
                    label = "إجمالي الصفقات",
                    value = "${metrics?.totalTrades ?: 0}",
                    modifier = Modifier.weight(1f)
                )
            }
        }

        // Secondary In-Depth Details Card
        metrics?.let { m ->
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(text = "إحصاءات التداول والمخاطر التفصيلية", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        HorizontalDivider(color = TradingBorder)

                        MetricRow("الصفقات الرابحة / الخاسرة", "${m.winningTrades} رابحة • ${m.losingTrades} خاسرة")
                        MetricRow(
                            "متوسط الربح / متوسط الخسارة",
                            "${m.avgWin?.let { String.format(Locale.US, "$%.2f", it) } ?: "N/A"} / ${m.avgLoss?.let { String.format(Locale.US, "$%.2f", it) } ?: "N/A"}"
                        )
                        MetricRow("أقصى تتابع صفقات رابحة", "${m.maxConsecutiveWins}")
                        MetricRow("أقصى تتابع صفقات خاسرة", "${m.maxConsecutiveLosses}")
                        MetricRow("أفضل صفقة", m.bestTrade?.let { String.format(Locale.US, "+$%.2f", it) } ?: "N/A")
                        MetricRow("أسوأ صفقة", m.worstTrade?.let { String.format(Locale.US, "$%.2f", it) } ?: "N/A")
                        MetricRow("متوسط مدة الصفقة", "${m.avgDurationMillis / 1000} ثانية (${m.avgDurationMillis / 60000} دقيقة)")
                        MetricRow("أقصر مدة صفقة", "${m.shortestDurationMillis / 1000} ثانية")
                        MetricRow("أطول مدة صفقة", "${m.longestDurationMillis / 60000} دقيقة")
                        MetricRow("إجمالي العقود (Volume)", String.format(Locale.US, "%.2f Lot", m.totalVolume))
                        MetricRow("متوسط العقد / أكبر عقد", "${String.format(Locale.US, "%.2f", m.avgVolume)} Lot / ${String.format(Locale.US, "%.2f", m.largestVolume)} Lot")
                        MetricRow("متوسط المخاطرة المحسوبة", m.avgRiskAmount?.let { String.format(Locale.US, "$%.2f", it) } ?: "N/A")
                        MetricRow("متوسط المضاعف R (R-Multiple)", m.avgRMultiple?.let { String.format(Locale.US, "%.2f R", it) } ?: "N/A")
                    }
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
        verticalArrangement = Arrangement.spacedBy(12.dp)
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
                shape = RoundedCornerShape(14.dp),
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
                    shape = RoundedCornerShape(10.dp),
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
