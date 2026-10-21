package com.example.feature.replay

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
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
import com.example.core.model.DataSourceType
import com.example.core.model.OrderSide
import com.example.core.model.OrderType
import com.example.core.model.PositionSide
import com.example.core.model.Timeframe
import com.example.ui.components.CandlestickChart
import com.example.ui.components.DataSourceBadge
import com.example.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReplayScreen(
    viewModel: ReplayViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val dateFormat = remember { SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US) }
    var showJumpDialog by remember { mutableStateOf(false) }
    var showOrderTicket by remember { mutableStateOf(false) }
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

            // 2. Large Central Candlestick Chart (Zero future candles, strictly visible subset!)
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                CandlestickChart(
                    candles = uiState.visibleCandles,
                    latestTick = uiState.latestTick,
                    openPositions = uiState.openPositions
                )
            }

            // 3. Playback Controls & Speed Selector
            Surface(
                color = TradingCard,
                border = androidx.compose.foundation.BorderStroke(1.dp, TradingBorder)
            ) {
                Column(modifier = Modifier.padding(10.dp)) {
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
