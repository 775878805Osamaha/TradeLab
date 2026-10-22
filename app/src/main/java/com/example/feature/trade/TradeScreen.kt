package com.example.feature.trade

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import com.example.core.model.*
import com.example.ui.components.CandlestickChart
import com.example.ui.components.DataSourceBadge
import com.example.ui.components.VirtualDisclaimerBanner
import com.example.ui.theme.*
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TradeScreen(
    viewModel: TradeViewModel,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val account = uiState.selectedAccount
    val tick = uiState.latestTick
    // A quiet/disconnected stream must expire on screen without requiring
    // another market tick or user interaction to trigger recomposition.
    var quoteClock by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.delay(1_000L)
            quoteClock = System.currentTimeMillis()
        }
    }
    val quoteIsVerified = tick != null &&
        tick.symbol == uiState.selectedSymbol &&
        tick.source in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL") &&
        quoteClock - tick.timestamp in 0..15_000L
    val verifiedTick = tick?.takeIf { quoteIsVerified }
    val symInfo = remember(uiState.selectedSymbol) { DefaultSymbols.getSymbol(uiState.selectedSymbol) }

    var showSymbolSheet by remember { mutableStateOf(false) }
    var showHistoricalKeyDialog by remember { mutableStateOf(false) }
    var historicalKeyInput by remember { mutableStateOf("") }
    var showPartialCloseDialog by remember { mutableStateOf<Position?>(null) }
    var partialCloseVolumeText by remember { mutableStateOf("0.01") }
    var showModifyDialog by remember { mutableStateOf<Position?>(null) }
    var modifySlText by remember { mutableStateOf("") }
    var modifyTpText by remember { mutableStateOf("") }
    var showTrailingStopDialog by remember { mutableStateOf<Position?>(null) }
    var trailingPipsText by remember { mutableStateOf("15.0") }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(uiState.message) {
        uiState.message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearMessage()
        }
    }

    if (showHistoricalKeyDialog) {
        AlertDialog(
            onDismissRequest = { showHistoricalKeyDialog = false },
            title = { Text("مصدر تاريخ الذهب والفوركس") },
            text = {
                OutlinedTextField(
                    value = historicalKeyInput,
                    onValueChange = { historicalKeyInput = it },
                    label = { Text("Twelve Data API Key") },
                    singleLine = true,
                    visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth().testTag("trade_twelvedata_key")
                )
            },
            confirmButton = {
                TextButton(
                    enabled = historicalKeyInput.isNotBlank(),
                    onClick = {
                        viewModel.configureHistoricalProviderKey(historicalKeyInput)
                        historicalKeyInput = ""
                        showHistoricalKeyDialog = false
                    }
                ) { Text("تحميل شموع حقيقية") }
            },
            dismissButton = { TextButton(onClick = { showHistoricalKeyDialog = false }) { Text("إلغاء") } }
        )
    }

    Scaffold(
        modifier = modifier.testTag("trade_screen"),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.clickable { showSymbolSheet = true }.testTag("trade_symbol_selector")
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
                        Spacer(modifier = Modifier.width(6.dp))
                        DataSourceBadge(sourceType = if (quoteIsVerified) DataSourceType.LIVE_DATA else DataSourceType.STALE_DATA)
                    }
                },
                actions = {
                    // Account Balance Quick Pill
                    account?.let { acc ->
                        Column(horizontalAlignment = Alignment.End, modifier = Modifier.padding(end = 12.dp)) {
                            Text(
                                text = "الحساب: ${acc.name}",
                                fontSize = 10.sp,
                                color = TradingTextSecondary,
                                maxLines = 1
                            )
                            Text(
                                text = String.format(Locale.US, "$%.2f", acc.balance),
                                style = TextStyle(textDirection = TextDirection.Ltr),
                                maxLines = 1,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                                color = TradingTextPrimary
                            )
                        }
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
                .padding(horizontal = 14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(bottom = 24.dp)
        ) {
            // 1. Mandatory Virtual Trading Disclaimer Banner
            item {
                VirtualDisclaimerBanner()
            }

            // 2. Real-time Market Quote & Spread Bar
            item {
                Card(
                    modifier = Modifier.fillMaxWidth().testTag("trade_quote_banner"),
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(text = "سعر العرض (Bid)", fontSize = 11.sp, color = TradingTextSecondary)
                            val bidStr = verifiedTick?.let { symInfo.formatPrice(it.bid) } ?: "--"
                            Text(text = bidStr, style = TextStyle(textDirection = TextDirection.Ltr), maxLines = 1, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = TradingTextPrimary)
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(text = "السبريد", fontSize = 10.sp, color = TradingTextSecondary)
                            val spreadPips = verifiedTick?.let { String.format(Locale.US, "%.1f", it.spread / symInfo.pipSize) } ?: "--"
                            Text(
                                text = "$spreadPips pips",
                                style = TextStyle(textDirection = TextDirection.Ltr),
                                maxLines = 1,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = TradingGold
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(text = "سعر الطلب (Ask)", fontSize = 11.sp, color = TradingTextSecondary)
                            val askStr = verifiedTick?.let { symInfo.formatPrice(it.ask) } ?: "--"
                            Text(text = askStr, style = TextStyle(textDirection = TextDirection.Ltr), maxLines = 1, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = TradingCyan)
                        }
                    }
                }
            }

            // 3. Compact Integrated Trading Chart
            item {
                Card(
                    modifier = Modifier.fillMaxWidth().height(180.dp).testTag("trade_chart_card"),
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Box(modifier = Modifier.fillMaxSize()) {
                        CandlestickChart(
                        candles = uiState.candles,
                        latestTick = uiState.latestTick,
                        openPositions = uiState.openPositions.filter { it.symbol == uiState.selectedSymbol },
                        modifier = Modifier.fillMaxSize()
                        )
                        if (uiState.isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.align(Alignment.Center).size(28.dp),
                                color = TradingCyan
                            )
                        } else if (uiState.candles.isEmpty()) {
                            Column(
                                modifier = Modifier.align(Alignment.Center).padding(12.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(
                                    text = "لا توجد شموع موثوقة لعرضها",
                                    fontSize = 12.sp,
                                    color = TradingTextSecondary
                                )
                                if (uiState.selectedSymbol !in setOf("BTCUSDT", "ETHUSDT") &&
                                    !viewModel.hasHistoricalProviderKey()) {
                                    TextButton(
                                        onClick = { showHistoricalKeyDialog = true },
                                        modifier = Modifier.testTag("trade_connect_historical_source")
                                    ) { Text("ربط بيانات الذهب والفوركس") }
                                } else {
                                    TextButton(
                                        onClick = { viewModel.retryCandleLoad() },
                                        modifier = Modifier.testTag("trade_chart_retry")
                                    ) { Text("إعادة المحاولة") }
                                }
                            }
                        }
                    }
                }
            }

            // 4. Order Execution Panel
            item {
                Card(
                    modifier = Modifier.fillMaxWidth().testTag("trade_order_panel"),
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        // Order Type Selector Chips
                        Text(text = "نوع الأمر الافتراضي:", fontSize = 12.sp, color = TradingTextSecondary)
                        Row(
                            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            listOf(
                                Pair(OrderType.MARKET, "سوقي Market"),
                                Pair(OrderType.BUY_LIMIT, "Buy Limit"),
                                Pair(OrderType.SELL_LIMIT, "Sell Limit"),
                                Pair(OrderType.BUY_STOP, "Buy Stop"),
                                Pair(OrderType.SELL_STOP, "Sell Stop")
                            ).forEach { (ot, title) ->
                                val isSelected = uiState.orderType == ot
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(if (isSelected) TradingAccent else TradingElevated)
                                        .clickable { viewModel.setOrderType(ot) }
                                        .padding(horizontal = 10.dp, vertical = 6.dp)
                                        .testTag("order_type_${ot.name}")
                                ) {
                                    Text(
                                        text = title,
                                        fontSize = 11.sp,
                                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                        color = if (isSelected) Color.White else TradingTextSecondary
                                    )
                                }
                            }
                        }

                        // Target Price for Pending Orders
                        if (uiState.orderType != OrderType.MARKET) {
                            OutlinedTextField(
                                value = uiState.requestedPrice,
                                onValueChange = { viewModel.setRequestedPrice(it) },
                                label = { Text("السعر المستهدف للأمر المعلق") },
                                modifier = Modifier.fillMaxWidth().testTag("order_requested_price_input"),
                                singleLine = true,
                                shape = RoundedCornerShape(8.dp)
                            )
                        }

                        // Volume Control with Quick +/- Buttons
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            OutlinedButton(
                                onClick = { viewModel.adjustVolume(-0.01) },
                                modifier = Modifier.size(44.dp),
                                contentPadding = PaddingValues(0.dp)
                            ) {
                                Text("-0.01", fontSize = 11.sp)
                            }
                            OutlinedTextField(
                                value = uiState.volume,
                                onValueChange = { viewModel.setVolume(it) },
                                label = { Text("حجم العقد (Lot)") },
                                modifier = Modifier.weight(1f).testTag("order_volume_input"),
                                singleLine = true,
                                shape = RoundedCornerShape(8.dp)
                            )
                            OutlinedButton(
                                onClick = { viewModel.adjustVolume(0.01) },
                                modifier = Modifier.size(44.dp),
                                contentPadding = PaddingValues(0.dp)
                            ) {
                                Text("+0.01", fontSize = 11.sp)
                            }
                        }

                        // Stop Loss & Take Profit Fields
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = uiState.stopLoss,
                                onValueChange = { viewModel.setStopLoss(it) },
                                label = { Text("وقف الخسارة SL") },
                                modifier = Modifier.weight(1f).testTag("order_sl_input"),
                                singleLine = true,
                                shape = RoundedCornerShape(8.dp)
                            )
                            OutlinedTextField(
                                value = uiState.takeProfit,
                                onValueChange = { viewModel.setTakeProfit(it) },
                                label = { Text("جني الأرباح TP") },
                                modifier = Modifier.weight(1f).testTag("order_tp_input"),
                                singleLine = true,
                                shape = RoundedCornerShape(8.dp)
                            )
                        }

                        // Live Pre-Trade Risk Calculator Preview
                        uiState.riskAnalysis?.let { risk ->
                            Surface(
                                color = TradingElevated,
                                shape = RoundedCornerShape(8.dp),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Column(modifier = Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                        Text(text = "الهامش المطلوب:", fontSize = 11.sp, color = TradingTextSecondary)
                                        Text(
                                            text = String.format(Locale.US, "$%.2f", risk.requiredMargin),
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = TradingTextPrimary
                                        )
                                    }
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                        Text(text = "الهامش المتاح بعد الأمر:", fontSize = 11.sp, color = TradingTextSecondary)
                                        Text(
                                            text = String.format(Locale.US, "$%.2f", risk.freeMarginRemaining),
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = if (risk.freeMarginRemaining > 0) TradingCyan else TradingNegative
                                        )
                                    }
                                    if (risk.potentialLoss > 0.0) {
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                            Text(text = "أقصى خسارة محتملة (Risk):", fontSize = 11.sp, color = TradingNegative)
                                            Text(
                                                text = String.format(Locale.US, "-$%.2f (%.1f%%)", risk.potentialLoss, risk.riskPercentage),
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.Bold,
                                                color = TradingNegative
                                            )
                                        }
                                    }
                                    if (risk.potentialProfit > 0.0) {
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                            Text(text = "أقصى ربح محتمل (Profit):", fontSize = 11.sp, color = TradingPositive)
                                            Text(
                                                text = String.format(Locale.US, "+$%.2f (R:R %.2f)", risk.potentialProfit, risk.riskRewardRatio ?: 0.0),
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.Bold,
                                                color = TradingPositive
                                            )
                                        }
                                    }
                                    if (risk.errorMessage != null) {
                                        Text(
                                            text = "تنبيه: ${risk.errorMessage}",
                                            color = TradingNegative,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Medium
                                        )
                                    }
                                }
                            }
                        }

                        // 5. Large One-Handed Action Controls (SELL and BUY) with Debouncing
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            // Large SELL Button (Red)
                            val bidText = verifiedTick?.let { symInfo.formatPrice(it.bid) } ?: "--"
                            Button(
                                onClick = { viewModel.placeOrder(OrderSide.SELL) },
                                modifier = Modifier
                                    .weight(1f)
                                    .height(56.dp)
                                    .testTag("action_sell_btn"),
                                shape = RoundedCornerShape(8.dp),
                                enabled = !uiState.isSubmittingOrder && quoteIsVerified,
                                colors = ButtonDefaults.buttonColors(containerColor = TradingNegative)
                            ) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text("بيع", fontSize = 15.sp, fontWeight = FontWeight.ExtraBold)
                                    Text(bidText, style = TextStyle(textDirection = TextDirection.Ltr), maxLines = 1, fontSize = 12.sp)
                                }
                            }

                            // Large BUY Button (Green)
                            val askText = verifiedTick?.let { symInfo.formatPrice(it.ask) } ?: "--"
                            Button(
                                onClick = { viewModel.placeOrder(OrderSide.BUY) },
                                modifier = Modifier
                                    .weight(1f)
                                    .height(56.dp)
                                    .testTag("action_buy_btn"),
                                shape = RoundedCornerShape(8.dp),
                                enabled = !uiState.isSubmittingOrder && quoteIsVerified,
                                colors = ButtonDefaults.buttonColors(containerColor = TradingPositive)
                            ) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text("شراء", fontSize = 15.sp, fontWeight = FontWeight.ExtraBold)
                                    Text(askText, style = TextStyle(textDirection = TextDirection.Ltr), maxLines = 1, fontSize = 12.sp)
                                }
                            }
                        }
                    }
                }
            }

            // 6. Open Positions Section Header
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "الصفقات المفتوحة (${uiState.openPositions.size})",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = TradingTextPrimary
                    )
                    val totalPl = uiState.openPositions.sumOf { it.netProfitLoss }
                    Text(
                        text = String.format(Locale.US, "المجمل: %s$%.2f", if (totalPl >= 0) "+" else "", totalPl),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (totalPl >= 0) TradingPositive else TradingNegative
                    )
                }
            }

            // Open Positions List
            if (uiState.openPositions.isEmpty()) {
                item {
                    Card(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                        colors = CardDefaults.cardColors(containerColor = TradingCard)
                    ) {
                        Box(modifier = Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                            Text(text = "لا توجد صفقات مفتوحة حالياً", color = TradingTextSecondary, fontSize = 13.sp)
                        }
                    }
                }
            } else {
                items(uiState.openPositions.size) { idx ->
                    val pos = uiState.openPositions[idx]
                    val isWin = pos.profitLoss >= 0.0
                    val posSym = DefaultSymbols.getSymbol(pos.symbol)

                    Card(
                        modifier = Modifier.fillMaxWidth().testTag("position_item_${pos.id}"),
                        shape = RoundedCornerShape(8.dp),
                        colors = CardDefaults.cardColors(containerColor = TradingCard),
                        border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                    ) {
                        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            // Row 1: Symbol + Direction Badge + Duration + P/L
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(text = pos.symbol, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(4.dp))
                                            .background(if (pos.side == PositionSide.BUY) TradingPositiveBg else TradingNegativeBg)
                                            .padding(horizontal = 6.dp, vertical = 2.dp)
                                    ) {
                                        Text(
                                            text = "${pos.side.name} ${pos.volume} lot",
                                            color = if (pos.side == PositionSide.BUY) TradingPositive else TradingNegative,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }
                                Column(horizontalAlignment = Alignment.End) {
                                    Text(
                                        text = String.format(Locale.US, "%s$%.2f", if (isWin) "+" else "", pos.netProfitLoss),
                                        color = if (isWin) TradingPositive else TradingNegative,
                                        fontWeight = FontWeight.ExtraBold,
                                        fontSize = 16.sp
                                    )
                                    Text(
                                        text = String.format(Locale.US, "%.1f%%", pos.pnlPercent),
                                        color = if (isWin) TradingPositive else TradingNegative,
                                        fontSize = 10.sp
                                    )
                                }
                            }

                            // Row 2: Entry, Current, SL, TP, Duration
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(
                                    text = "الدخول: ${posSym.formatPrice(pos.entryPrice)} | الحالي: ${posSym.formatPrice(pos.currentPrice)}",
                                    fontSize = 11.sp,
                                    color = TradingTextSecondary
                                )
                                Text(text = pos.durationFormatted, fontSize = 11.sp, color = TradingTextMuted)
                            }

                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(
                                    text = "SL: ${pos.stopLoss?.let { posSym.formatPrice(it) } ?: "غير محدد"}",
                                    fontSize = 11.sp,
                                    color = if (pos.stopLoss != null) TradingNegative else TradingTextMuted
                                )
                                Text(
                                    text = "TP: ${pos.takeProfit?.let { posSym.formatPrice(it) } ?: "غير محدد"}",
                                    fontSize = 11.sp,
                                    color = if (pos.takeProfit != null) TradingPositive else TradingTextMuted
                                )
                                Text(
                                    text = "الهامش: $${String.format(Locale.US, "%.1f", pos.margin)}",
                                    fontSize = 11.sp,
                                    color = TradingCyan
                                )
                            }

                            HorizontalDivider(color = TradingBorder)

                            // Position Actions: CLOSE, PARTIAL CLOSE, MODIFY, BREAK EVEN, TRAILING STOP
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                OutlinedButton(
                                    onClick = {
                                        showModifyDialog = pos
                                        modifySlText = pos.stopLoss?.toString() ?: ""
                                        modifyTpText = pos.takeProfit?.toString() ?: ""
                                    },
                                    modifier = Modifier.weight(1f),
                                    contentPadding = PaddingValues(horizontal = 2.dp)
                                ) {
                                    Text("تعديل", fontSize = 10.sp)
                                }

                                OutlinedButton(
                                    onClick = { viewModel.setBreakEven(pos.id) },
                                    modifier = Modifier.weight(1f),
                                    contentPadding = PaddingValues(horizontal = 2.dp)
                                ) {
                                    Text("تعادل BE", fontSize = 10.sp)
                                }

                                OutlinedButton(
                                    onClick = { showTrailingStopDialog = pos },
                                    modifier = Modifier.weight(1f),
                                    contentPadding = PaddingValues(horizontal = 2.dp)
                                ) {
                                    Text("وقف متحرك", fontSize = 10.sp)
                                }

                                OutlinedButton(
                                    onClick = {
                                        showPartialCloseDialog = pos
                                        partialCloseVolumeText = String.format(Locale.US, "%.2f", (pos.volume / 2.0).coerceAtLeast(0.01))
                                    },
                                    modifier = Modifier.weight(1f),
                                    contentPadding = PaddingValues(horizontal = 2.dp)
                                ) {
                                    Text("إغلاق جزئي", fontSize = 10.sp)
                                }

                                Button(
                                    onClick = { viewModel.closePosition(pos.id) },
                                    colors = ButtonDefaults.buttonColors(containerColor = TradingNegative),
                                    modifier = Modifier.weight(1f),
                                    contentPadding = PaddingValues(horizontal = 2.dp)
                                ) {
                                    Text("إغلاق كلي", fontSize = 10.sp)
                                }
                            }
                        }
                    }
                }
            }

            // 7. Pending Orders Section (if any)
            if (uiState.pendingOrders.isNotEmpty()) {
                item {
                    Text(
                        text = "الأوامر المعلقة (${uiState.pendingOrders.size})",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = TradingTextPrimary,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }

                items(uiState.pendingOrders.size) { idx ->
                    val po = uiState.pendingOrders[idx]
                    Card(
                        modifier = Modifier.fillMaxWidth().testTag("pending_order_${po.id}"),
                        shape = RoundedCornerShape(8.dp),
                        colors = CardDefaults.cardColors(containerColor = TradingElevated)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(
                                    text = "${po.type.displayNameAr} • ${po.symbol}",
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 13.sp
                                )
                                Text(
                                    text = "السعر: ${po.requestedPrice} | الحجم: ${po.volume} lot",
                                    fontSize = 11.sp,
                                    color = TradingTextSecondary
                                )
                            }
                            IconButton(onClick = { viewModel.cancelPendingOrder(po.id) }) {
                                Icon(Icons.Default.DeleteOutline, contentDescription = "إلغاء الأمر", tint = TradingNegative)
                            }
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
            Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                Text(text = "اختر رمز التداول الافتراضي", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
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

    // Partial Close Dialog
    showPartialCloseDialog?.let { pos ->
        AlertDialog(
            onDismissRequest = { showPartialCloseDialog = null },
            title = { Text("إغلاق جزئي للصفقة #${pos.id}") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(text = "الحجم الكلي الحالي: ${pos.volume} lot", fontSize = 12.sp, color = TradingTextSecondary)
                    OutlinedTextField(
                        value = partialCloseVolumeText,
                        onValueChange = { partialCloseVolumeText = it },
                        label = { Text("اللوت المراد إغلاقه") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val vol = partialCloseVolumeText.toDoubleOrNull() ?: 0.01
                        viewModel.partialClosePosition(pos.id, vol)
                        showPartialCloseDialog = null
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = TradingNegative)
                ) {
                    Text("تنفيذ الإغلاق الجزئي")
                }
            },
            dismissButton = {
                TextButton(onClick = { showPartialCloseDialog = null }) { Text("إلغاء") }
            }
        )
    }

    // Modify SL / TP Dialog
    showModifyDialog?.let { pos ->
        AlertDialog(
            onDismissRequest = { showModifyDialog = null },
            title = { Text("تعديل مستويات الصفقة #${pos.id}") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = modifySlText,
                        onValueChange = { modifySlText = it },
                        label = { Text("وقف الخسارة SL (فارغ للحذف)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = modifyTpText,
                        onValueChange = { modifyTpText = it },
                        label = { Text("جني الأرباح TP (فارغ للحذف)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val sl = modifySlText.toDoubleOrNull()
                        val tp = modifyTpText.toDoubleOrNull()
                        viewModel.modifyPosition(pos.id, sl, tp)
                        showModifyDialog = null
                    }
                ) {
                    Text("حفظ التعديلات")
                }
            },
            dismissButton = {
                TextButton(onClick = { showModifyDialog = null }) { Text("إلغاء") }
            }
        )
    }

    // Trailing Stop Dialog
    showTrailingStopDialog?.let { pos ->
        AlertDialog(
            onDismissRequest = { showTrailingStopDialog = null },
            title = { Text("ضبط الوقف المتحرك Trailing Stop") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(text = "سيقوم النظام بتحديث وقف الخسارة تلقائياً كلما تحرك السعر في اتجاه الربح.", fontSize = 12.sp, color = TradingTextSecondary)
                    OutlinedTextField(
                        value = trailingPipsText,
                        onValueChange = { trailingPipsText = it },
                        label = { Text("المسافة بالنقط (Pips)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val pips = trailingPipsText.toDoubleOrNull() ?: 15.0
                        viewModel.setTrailingStop(pos.id, pips)
                        showTrailingStopDialog = null
                    }
                ) {
                    Text("تفعيل الوقف المتحرك")
                }
            },
            dismissButton = {
                TextButton(onClick = { showTrailingStopDialog = null }) { Text("إلغاء") }
            }
        )
    }
}
