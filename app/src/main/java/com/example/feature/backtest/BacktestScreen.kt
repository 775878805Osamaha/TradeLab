package com.example.feature.backtest

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
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
import com.example.core.analytics.EquityAnalytics
import com.example.core.analytics.EquityCsvExporter
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File
import androidx.compose.ui.platform.LocalContext
import com.example.core.market.DefaultSymbols
import com.example.core.model.PositionSide
import com.example.core.model.PositionSizingMode
import com.example.core.model.Timeframe
import com.example.ui.components.EquityCurveChart
import com.example.ui.components.StatTile
import com.example.ui.theme.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BacktestScreen(
    viewModel: BacktestViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val sdf = remember { SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.US) }

    LaunchedEffect(uiState.message) {
        uiState.message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearMessage()
        }
    }

    Scaffold(
        modifier = modifier.testTag("backtest_screen"),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("محاكي الاختبار التاريخي (Backtest)", fontSize = 17.sp, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
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
            // Main Navigation Tabs
            TabRow(
                selectedTabIndex = uiState.selectedTab.ordinal,
                containerColor = TradingCard,
                contentColor = TradingAccent,
                modifier = Modifier.fillMaxWidth()
            ) {
                Tab(
                    selected = uiState.selectedTab == BacktestTab.CONFIG,
                    onClick = { viewModel.setSelectedTab(BacktestTab.CONFIG) },
                    text = { Text("الإعدادات", fontWeight = FontWeight.Bold, fontSize = 13.sp) }
                )
                Tab(
                    selected = uiState.selectedTab == BacktestTab.RESULTS,
                    onClick = { viewModel.setSelectedTab(BacktestTab.RESULTS) },
                    text = {
                        Text(
                            text = if (uiState.lastResult != null) "النتائج (${uiState.lastResult?.trades?.size ?: 0})" else "النتائج",
                            fontWeight = FontWeight.Bold,
                            fontSize = 13.sp
                        )
                    }
                )
                Tab(
                    selected = uiState.selectedTab == BacktestTab.HISTORY,
                    onClick = { viewModel.setSelectedTab(BacktestTab.HISTORY) },
                    text = {
                        Text(
                            text = "السجل (${uiState.pastRuns.size})",
                            fontWeight = FontWeight.Bold,
                            fontSize = 13.sp
                        )
                    }
                )
            }

            when (uiState.selectedTab) {
                BacktestTab.CONFIG -> BacktestConfigContent(viewModel = viewModel, uiState = uiState)
                BacktestTab.RESULTS -> BacktestResultsContent(viewModel = viewModel, uiState = uiState)
                BacktestTab.HISTORY -> BacktestHistoryContent(viewModel = viewModel, uiState = uiState, sdf = sdf)
            }
        }
    }
}

@Composable
private fun BacktestConfigContent(
    viewModel: BacktestViewModel,
    uiState: BacktestUiState
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
    ) {
        // 1. Strategy Selection
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(text = "اختر الاستراتيجية الخوارزمية", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(modifier = Modifier.height(10.dp))
                    if (uiState.availableStrategies.isEmpty()) {
                        Text(
                            text = "لا توجد استراتيجيات مدمجة حالياً. يمكنك تسجيل استراتيجيات مخصصة للبدء في الاختبار.",
                            fontSize = 12.sp,
                            color = TradingTextSecondary,
                            modifier = Modifier.padding(vertical = 8.dp)
                        )
                    } else {
                        uiState.availableStrategies.forEach { st ->
                            val isSel = uiState.selectedStrategy?.id == st.id
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (isSel) TradingElevated else Color.Transparent)
                                    .clickable { viewModel.selectStrategy(st) }
                                    .padding(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                RadioButton(
                                    selected = isSel,
                                    onClick = { viewModel.selectStrategy(st) }
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Column {
                                    Text(text = st.name, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                                    Text(text = st.description, fontSize = 11.sp, color = TradingTextSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Symbol & Timeframe Settings
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(text = "رمز الأداة والإطار الزمني", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(modifier = Modifier.height(10.dp))

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        DefaultSymbols.SYMBOLS.take(4).forEach { s ->
                            val isSel = uiState.symbol == s.symbol
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (isSel) TradingAccent else TradingElevated)
                                    .clickable { viewModel.selectSymbol(s.symbol) }
                                    .padding(horizontal = 10.dp, vertical = 6.dp)
                            ) {
                                Text(
                                    text = s.symbol,
                                    fontSize = 12.sp,
                                    fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal,
                                    color = if (isSel) Color.White else TradingTextSecondary
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(Timeframe.M5, Timeframe.M15, Timeframe.H1, Timeframe.H4, Timeframe.D1).forEach { tf ->
                            val isSel = uiState.timeframe == tf
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (isSel) TradingAccent else TradingElevated)
                                    .clickable { viewModel.selectTimeframe(tf) }
                                    .padding(horizontal = 8.dp, vertical = 4.dp)
                            ) {
                                Text(
                                    text = tf.displayName,
                                    fontSize = 11.sp,
                                    fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal,
                                    color = if (isSel) Color.White else TradingTextSecondary
                                )
                            }
                        }
                    }
                }
            }
        }

        // 3. Position Sizing Mode & Risk Management
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(text = "إدارة المخاطر وتحديد حجم العقود", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(modifier = Modifier.height(10.dp))

                    // Position Sizing Mode Selector
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        PositionSizingMode.values().forEach { mode ->
                            val isSel = uiState.positionSizingMode == mode
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (isSel) TradingElevated else Color.Transparent)
                                    .clickable { viewModel.setPositionSizingMode(mode) }
                                    .padding(vertical = 4.dp, horizontal = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                RadioButton(
                                    selected = isSel,
                                    onClick = { viewModel.setPositionSizingMode(mode) }
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(text = mode.displayNameAr, fontSize = 12.sp, fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal)
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        OutlinedTextField(
                            value = uiState.initialBalance,
                            onValueChange = { viewModel.setInitialBalance(it) },
                            label = { Text("الرصيد المبدئي ($)") },
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )

                        when (uiState.positionSizingMode) {
                            PositionSizingMode.FIXED_LOT -> {
                                OutlinedTextField(
                                    value = uiState.fixedLotSize,
                                    onValueChange = { viewModel.setFixedLotSize(it) },
                                    label = { Text("حجم العقد (Lot)") },
                                    modifier = Modifier.weight(1f),
                                    singleLine = true
                                )
                            }
                            PositionSizingMode.RISK_PERCENTAGE -> {
                                OutlinedTextField(
                                    value = uiState.riskPercentage,
                                    onValueChange = { viewModel.setRiskPercentage(it) },
                                    label = { Text("نسبة المخاطرة %") },
                                    modifier = Modifier.weight(1f),
                                    singleLine = true
                                )
                            }
                            PositionSizingMode.FIXED_MONETARY_RISK -> {
                                OutlinedTextField(
                                    value = uiState.fixedRiskAmount,
                                    onValueChange = { viewModel.setFixedRiskAmount(it) },
                                    label = { Text("مبلغ المخاطرة ($)") },
                                    modifier = Modifier.weight(1f),
                                    singleLine = true
                                )
                            }
                        }
                    }
                }
            }
        }

        // 4. Execution Costs & Market Simulation Parameters
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(text = "تكاليف التنفيذ والرافعة المالية", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(modifier = Modifier.height(10.dp))

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = uiState.leverage,
                            onValueChange = { viewModel.setLeverage(it) },
                            label = { Text("الرافعة 1:") },
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                        OutlinedTextField(
                            value = uiState.spreadPips,
                            onValueChange = { viewModel.setSpreadPips(it) },
                            label = { Text("الفارق (Pips)") },
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = uiState.commission,
                            onValueChange = { viewModel.setCommission(it) },
                            label = { Text("العمولة ($/Lot)") },
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                        OutlinedTextField(
                            value = uiState.slippage,
                            onValueChange = { viewModel.setSlippage(it) },
                            label = { Text("الانزلاق (Pips)") },
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                    }
                }
            }
        }

        // 5. Direction & Position Constraints
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(text = "قواعد واتجاهات الدخول", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(modifier = Modifier.height(8.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = "السماح بصفقات الشراء (Long)", fontSize = 13.sp)
                        Switch(
                            checked = uiState.allowLong,
                            onCheckedChange = { viewModel.setAllowLong(it) }
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = "السماح بصفقات البيع (Short)", fontSize = 13.sp)
                        Switch(
                            checked = uiState.allowShort,
                            onCheckedChange = { viewModel.setAllowShort(it) }
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = "السماح بتعدد الصفقات المفتوحة معاً", fontSize = 13.sp)
                        Switch(
                            checked = uiState.allowMultiplePositions,
                            onCheckedChange = { viewModel.setAllowMultiplePositions(it) }
                        )
                    }
                }
            }
        }

        // 6. Execution Progress Banner (if active)
        if (uiState.isRunning) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingElevated),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingAccent))
                ) {
                    Column(modifier = Modifier.padding(14.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp), color = TradingAccent, strokeWidth = 2.dp)
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = uiState.currentStage?.descriptionAr ?: "جاري معالجة البيانات...",
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = TradingTextPrimary
                                )
                            }
                            Text(
                                text = "${(uiState.progressFraction * 100).toInt()}%",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                                color = TradingAccentLight
                            )
                        }
                        Spacer(modifier = Modifier.height(10.dp))
                        LinearProgressIndicator(
                            progress = { uiState.progressFraction },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(6.dp)
                                .clip(RoundedCornerShape(3.dp)),
                            color = TradingAccent,
                            trackColor = TradingBorder
                        )
                    }
                }
            }
        }

        // 7. Actions: Start / Cancel / Reset
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (uiState.isRunning) {
                    Button(
                        onClick = { viewModel.cancelBacktest() },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(48.dp)
                            .testTag("cancel_backtest_btn"),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingNegative)
                    ) {
                        Icon(Icons.Default.Close, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("إلغاء الاختبار التاريخي بأمان", fontWeight = FontWeight.Bold)
                    }
                } else {
                    OutlinedButton(
                        onClick = { viewModel.resetBacktest() },
                        modifier = Modifier.weight(0.8f).height(48.dp)
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("إعادة الضبط")
                    }

                    Button(
                        onClick = { viewModel.runBacktest() },
                        enabled = uiState.selectedStrategy != null,
                        modifier = Modifier
                            .weight(1.2f)
                            .height(48.dp)
                            .testTag("start_backtest_btn"),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingAccent)
                    ) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("بدء الاختبار التاريخي")
                    }
                }
            }
        }
    }
}

@Composable
private fun BacktestResultsContent(
    viewModel: BacktestViewModel,
    uiState: BacktestUiState
) {
    val result = uiState.lastResult
    if (result == null) {
        Box(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "لا توجد نتائج اختبار حالية",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = TradingTextSecondary
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "قم بضبط الإعدادات في تبويب الإعدادات ثم اضغط على 'بدء الاختبار التاريخي'.",
                    fontSize = 12.sp,
                    color = TradingTextMuted
                )
                Spacer(modifier = Modifier.height(16.dp))
                Button(
                    onClick = { viewModel.setSelectedTab(BacktestTab.CONFIG) },
                    colors = ButtonDefaults.buttonColors(containerColor = TradingAccent)
                ) {
                    Text("الانتقال إلى الإعدادات")
                }
            }
        }
        return
    }

    val m = result.metrics
    val shareContext = LocalContext.current
    val equityInsights = remember(result.equityCurve) {
        runCatching {
            EquityAnalytics.summarize(
                result.equityCurve.map { point ->
                    EquityAnalytics.Point(point.timestamp, point.equity)
                }
            )
        }.getOrNull()
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
    ) {
        // Results Header & Mode Switch
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = result.config.strategy.name,
                        fontWeight = FontWeight.Bold,
                        fontSize = 15.sp,
                        color = TradingGold
                    )
                    Text(
                        text = "${result.config.symbol} • ${result.config.timeframe.displayName} • ${result.totalCandlesProcessed} شمعة",
                        fontSize = 12.sp,
                        color = TradingTextSecondary
                    )
                }

                // Switch VALUE vs PERCENTAGE
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(TradingElevated)
                        .padding(2.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (uiState.displayMode == ResultsDisplayMode.VALUE) TradingAccent else Color.Transparent)
                            .clickable { viewModel.setDisplayMode(ResultsDisplayMode.VALUE) }
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text(
                            text = "بالقيمة ($)",
                            fontSize = 11.sp,
                            fontWeight = if (uiState.displayMode == ResultsDisplayMode.VALUE) FontWeight.Bold else FontWeight.Normal,
                            color = if (uiState.displayMode == ResultsDisplayMode.VALUE) Color.White else TradingTextSecondary
                        )
                    }
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (uiState.displayMode == ResultsDisplayMode.PERCENTAGE) TradingAccent else Color.Transparent)
                            .clickable { viewModel.setDisplayMode(ResultsDisplayMode.PERCENTAGE) }
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text(
                            text = "بالنسبة (%)",
                            fontSize = 11.sp,
                            fontWeight = if (uiState.displayMode == ResultsDisplayMode.PERCENTAGE) FontWeight.Bold else FontWeight.Normal,
                            color = if (uiState.displayMode == ResultsDisplayMode.PERCENTAGE) Color.White else TradingTextSecondary
                        )
                    }
                }
            }
        }

        // Equity Curve Chart
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(text = "منحنى رأس المال والتراجع (Equity Curve)", fontSize = 12.sp, color = TradingTextSecondary)
                    Spacer(modifier = Modifier.height(8.dp))
                    EquityCurveChart(
                        points = result.equityCurve,
                        initialBalance = result.config.initialBalance
                    )
                }
            }
        }

        // Independently validated equity analytics: do not display misleading
        // drawdown or streaks if the underlying equity series is invalid.
        equityInsights?.let { insights ->
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("تحليل منحنى رأس المال", fontWeight = FontWeight.Bold, color = TradingTextPrimary)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatTile(
                            label = "أقصى تراجع",
                            value = String.format(Locale.US, "%.2f%%", insights.maxDrawdown.percent),
                            isPositive = insights.maxDrawdown.percent == 0.0,
                            modifier = Modifier.weight(1f)
                        )
                        StatTile(
                            label = "الفترات الرابحة",
                            value = String.format(Locale.US, "%.1f%%", insights.periodWinRatePercent),
                            isPositive = insights.periodWinRatePercent >= 50.0,
                            modifier = Modifier.weight(1f)
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatTile(
                            label = "أطول سلسلة ربح",
                            value = insights.longestWinningStreak.toString(),
                            isPositive = true,
                            modifier = Modifier.weight(1f)
                        )
                        StatTile(
                            label = "أطول سلسلة خسارة",
                            value = insights.longestLosingStreak.toString(),
                            isPositive = false,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }

        item {
            OutlinedButton(
                onClick = {
                    runCatching {
                        val points = result.equityCurve.map { point ->
                            EquityAnalytics.Point(point.timestamp, point.equity)
                        }
                        val exportDir = File(shareContext.cacheDir, "backtest_exports").apply { mkdirs() }
                        val exportFile = File.createTempFile("tradelab_equity_", ".csv", exportDir)
                        try {
                            exportFile.bufferedWriter(Charsets.UTF_8).use { writer ->
                                EquityCsvExporter.write(points, writer)
                            }
                        } catch (failure: Exception) {
                            exportFile.delete()
                            throw failure
                        }
                        val uri = FileProvider.getUriForFile(
                            shareContext,
                            "${shareContext.packageName}.fileprovider",
                            exportFile
                        )
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/csv"
                            putExtra(Intent.EXTRA_SUBJECT, "TradeLab backtest equity curve")
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            clipData = android.content.ClipData.newUri(
                                shareContext.contentResolver, "TradeLab equity CSV", uri
                            )
                        }
                        shareContext.startActivity(Intent.createChooser(intent, "مشاركة نتائج الباك تيست"))
                    }
                },
                modifier = Modifier.fillMaxWidth().testTag("backtest_share_equity_csv")
            ) {
                Text("مشاركة بيانات منحنى رأس المال CSV")
            }
        }

        // Primary Metric Tiles
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                StatTile(
                    label = "صافي الربح",
                    value = String.format(Locale.US, "%s$%.2f", if (m.netProfit >= 0) "+" else "", m.netProfit),
                    isPositive = m.netProfit >= 0,
                    modifier = Modifier.weight(1f)
                )
                StatTile(
                    label = "نسبة العائد %",
                    value = String.format(Locale.US, "%s%.1f%%", if (m.returnPct >= 0) "+" else "", m.returnPct),
                    isPositive = m.returnPct >= 0,
                    modifier = Modifier.weight(1f)
                )
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                StatTile(
                    label = "عامل الربح (PF)",
                    value = m.profitFactor?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A",
                    modifier = Modifier.weight(1f)
                )
                StatTile(
                    label = "معدل الفوز (Win Rate)",
                    value = String.format(Locale.US, "%.1f%%", m.winRatePct),
                    isPositive = m.winRatePct >= 50,
                    modifier = Modifier.weight(1f)
                )
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                StatTile(
                    label = "أقصى تراجع (Drawdown)",
                    value = String.format(Locale.US, "%.1f%% ($%.2f)", m.maxDrawdownPct, m.maxDrawdown),
                    isPositive = false,
                    modifier = Modifier.weight(1f)
                )
                StatTile(
                    label = "التوقع الرياضي (Expectancy)",
                    value = m.expectancy?.let { String.format(Locale.US, "$%.2f", it) } ?: "N/A",
                    isPositive = (m.expectancy ?: 0.0) >= 0.0,
                    modifier = Modifier.weight(1f)
                )
            }
        }

        // Secondary Metrics Grid
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(text = "إحصاءات تفصيلية متقدمة", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    HorizontalDivider(color = TradingBorder)

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(text = "إجمالي الصفقات المنفذة", fontSize = 12.sp, color = TradingTextSecondary)
                        Text(text = "${m.totalTrades} (${m.winningTrades} رابحة • ${m.losingTrades} خاسرة)", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(text = "متوسط الربح / متوسط الخسارة", fontSize = 12.sp, color = TradingTextSecondary)
                        Text(
                            text = "${m.avgWin?.let { String.format(Locale.US, "$%.2f", it) } ?: "N/A"} / ${m.avgLoss?.let { String.format(Locale.US, "$%.2f", it) } ?: "N/A"}",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(text = "نسبة شارب (Sharpe) / سورتينو (Sortino)", fontSize = 12.sp, color = TradingTextSecondary)
                        Text(
                            text = "${m.sharpeRatio?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A"} / ${m.sortinoRatio?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A"}",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(text = "عامل التعافي (Recovery Factor)", fontSize = 12.sp, color = TradingTextSecondary)
                        Text(text = m.recoveryFactor?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(text = "أفضل صفقة / أسوأ صفقة", fontSize = 12.sp, color = TradingTextSecondary)
                        Text(
                            text = "${m.bestTrade?.let { String.format(Locale.US, "+$%.2f", it) } ?: "N/A"} / ${m.worstTrade?.let { String.format(Locale.US, "$%.2f", it) } ?: "N/A"}",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }

        // Daily Results Breakdown (Section 18)
        if (result.dailySummaries.isNotEmpty()) {
            item {
                Text(
                    text = "توزيع النتائج اليومية (${result.dailySummaries.size} يوم)",
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    color = TradingTextPrimary,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }

            items(result.dailySummaries.take(7)) { day ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(text = day.fullDate, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                            Text(
                                text = "${day.tradeCount} صفقات • حجم: ${String.format(Locale.US, "%.2f", day.totalLots)} Lot",
                                fontSize = 11.sp,
                                color = TradingTextSecondary
                            )
                        }
                        Text(
                            text = String.format(Locale.US, "%s$%.2f", if (day.profitLoss >= 0) "+" else "", day.profitLoss),
                            fontWeight = FontWeight.Bold,
                            fontSize = 13.sp,
                            color = if (day.profitLoss >= 0) TradingPositive else TradingNegative
                        )
                    }
                }
            }
        }

        // Trades List
        if (result.trades.isNotEmpty()) {
            item {
                Text(
                    text = "سجل الصفقات المنفذة (${result.trades.size} صفقة)",
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    color = TradingTextPrimary,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }

            items(result.trades.take(15)) { trade ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(10.dp),
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
                                    text = if (trade.side == PositionSide.BUY) "شراء" else "بيع",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (trade.side == PositionSide.BUY) TradingPositive else TradingNegative
                                )
                            }
                            Spacer(modifier = Modifier.width(8.dp))
                            Column {
                                Text(text = "${trade.symbol} • ${trade.volume} Lot", fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                                Text(
                                    text = "دخول: ${trade.entryPrice} -> خروج: ${trade.exitPrice}",
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
private fun BacktestHistoryContent(
    viewModel: BacktestViewModel,
    uiState: BacktestUiState,
    sdf: SimpleDateFormat
) {
    if (uiState.pastRuns.isEmpty()) {
        Box(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "سجل الاختبارات التاريخية فارغ",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = TradingTextSecondary
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "كل اختبار يتم تشغيله واكتماله سيتم حفظه هنا تلقائياً في قاعدة البيانات.",
                    fontSize = 12.sp,
                    color = TradingTextMuted
                )
            }
        }
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
    ) {
        items(uiState.pastRuns, key = { it.id }) { run ->
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(10.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard),
                border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(text = run.strategyName, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            Text(
                                text = "${run.symbol} • ${run.timeframe.displayName} • ${sdf.format(Date(run.startedAt))}",
                                fontSize = 11.sp,
                                color = TradingTextSecondary
                            )
                        }

                        IconButton(onClick = { viewModel.deleteRun(run.id) }) {
                            Icon(Icons.Default.Delete, contentDescription = "حذف", tint = TradingTextMuted, modifier = Modifier.size(18.dp))
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))
                    HorizontalDivider(color = TradingBorder)
                    Spacer(modifier = Modifier.height(8.dp))

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column {
                            Text(text = "صافي الربح", fontSize = 10.sp, color = TradingTextSecondary)
                            Text(
                                text = String.format(Locale.US, "%s$%.2f", if (run.netProfit >= 0) "+" else "", run.netProfit),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (run.netProfit >= 0) TradingPositive else TradingNegative
                            )
                        }
                        Column {
                            Text(text = "العائد %", fontSize = 10.sp, color = TradingTextSecondary)
                            Text(
                                text = String.format(Locale.US, "%s%.1f%%", if (run.returnPercentage >= 0) "+" else "", run.returnPercentage),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (run.returnPercentage >= 0) TradingPositive else TradingNegative
                            )
                        }
                        Column {
                            Text(text = "معدل الفوز", fontSize = 10.sp, color = TradingTextSecondary)
                            Text(text = String.format(Locale.US, "%.1f%%", run.winRate), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                        Column {
                            Text(text = "عامل الربح", fontSize = 10.sp, color = TradingTextSecondary)
                            Text(text = run.profitFactor?.let { String.format(Locale.US, "%.2f", it) } ?: "N/A", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                        Column {
                            Text(text = "الصفقات", fontSize = 10.sp, color = TradingTextSecondary)
                            Text(text = "${run.totalTrades}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
        }
    }
}
