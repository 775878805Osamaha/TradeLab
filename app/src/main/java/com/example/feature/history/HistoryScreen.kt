package com.example.feature.history

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.market.DefaultSymbols
import com.example.core.model.ExitReason
import com.example.core.model.PositionSide
import com.example.core.model.TradeJournalEntry
import com.example.ui.theme.*
import com.example.feature.results.TradeDetailDialog
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val dateFormat = remember { SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US) }
    var selectedTradeForDetail by remember { mutableStateOf<TradeJournalEntry?>(null) }

    selectedTradeForDetail?.let { trade ->
        TradeDetailDialog(trade = trade, onDismiss = { selectedTradeForDetail = null })
    }

    Scaffold(
        modifier = modifier.testTag("history_screen"),
        topBar = {
            TopAppBar(
                title = { Text("سجل ويوميات الصفقات", fontSize = 17.sp, fontWeight = FontWeight.Bold) },
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
                .padding(horizontal = 14.dp)
        ) {
            // Metrics summary banner
            Card(
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                shape = RoundedCornerShape(10.dp),
                colors = CardDefaults.cardColors(containerColor = TradingCard)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(text = "الصفقات: ${uiState.totalTradesCount}", fontSize = 11.sp, color = TradingTextSecondary)
                    Text(
                        text = "نسبة الفوز: ${String.format(Locale.US, "%.1f%%", uiState.winRatePct)}",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (uiState.winRatePct >= 50.0) TradingPositive else TradingTextPrimary
                    )
                    Text(
                        text = String.format(Locale.US, "الصافي: %s$%.2f", if (uiState.totalNetProfit >= 0) "+" else "", uiState.totalNetProfit),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (uiState.totalNetProfit >= 0) TradingPositive else TradingNegative
                    )
                }
            }

            // 9 Tabs: ALL, WIN, LOSS, BUY, SELL, SL, TP, MANUAL, STRATEGY
            ScrollableTabRow(
                selectedTabIndex = uiState.selectedTab.ordinal,
                containerColor = TradingCard,
                contentColor = TradingTextPrimary,
                edgePadding = 0.dp,
                modifier = Modifier.clip(RoundedCornerShape(10.dp))
            ) {
                HistoryTab.values().forEach { tab ->
                    Tab(
                        selected = uiState.selectedTab == tab,
                        onClick = { viewModel.selectTab(tab) },
                        text = {
                            Text(
                                text = tab.displayNameAr,
                                fontSize = 11.sp,
                                fontWeight = if (uiState.selectedTab == tab) FontWeight.Bold else FontWeight.Normal
                            )
                        },
                        modifier = Modifier.testTag("history_tab_${tab.name}")
                    )
                }
            }

            Spacer(modifier = Modifier.height(10.dp))

            if (uiState.trades.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.Inbox, contentDescription = null, tint = TradingTextSecondary, modifier = Modifier.size(48.dp))
                        Spacer(modifier = Modifier.height(8.dp))
                        Text("لا توجد صفقات مسجلة في هذا القسم", color = TradingTextSecondary)
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    contentPadding = PaddingValues(bottom = 20.dp)
                ) {
                    items(uiState.trades.size) { index ->
                        val trade = uiState.trades[index]
                        val isWin = trade.netProfitLoss >= 0.0
                        val sym = DefaultSymbols.getSymbol(trade.symbol)

                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { selectedTradeForDetail = trade }
                                .testTag("trade_journal_card_${trade.id}"),
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(containerColor = TradingCard),
                            border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                        ) {
                            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                // Row 1: ID, Symbol, Direction, Net P/L
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(text = "#${trade.id} ${trade.symbol}", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                        Spacer(modifier = Modifier.width(6.dp))
                                        Box(
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(4.dp))
                                                .background(if (trade.side == PositionSide.BUY) TradingPositiveBg else TradingNegativeBg)
                                                .padding(horizontal = 6.dp, vertical = 2.dp)
                                        ) {
                                            Text(
                                                text = "${if (trade.side == PositionSide.BUY) "BUY" else "SELL"} ${trade.volume} lot",
                                                color = if (trade.side == PositionSide.BUY) TradingPositive else TradingNegative,
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.Bold
                                            )
                                        }
                                    }
                                    Text(
                                        text = String.format(Locale.US, "%s$%.2f", if (isWin) "+" else "", trade.netProfitLoss),
                                        color = if (isWin) TradingPositive else TradingNegative,
                                        fontWeight = FontWeight.ExtraBold,
                                        fontSize = 16.sp
                                    )
                                }

                                // Row 2: Entry, Exit, SL, TP
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(text = "الدخول: ${sym.formatPrice(trade.entryPrice)}", fontSize = 11.sp, color = TradingTextSecondary)
                                    Text(text = "الخروج: ${sym.formatPrice(trade.exitPrice)}", fontSize = 11.sp, color = TradingTextSecondary)
                                }

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(
                                        text = "SL: ${trade.stopLoss?.let { sym.formatPrice(it) } ?: "--"} | TP: ${trade.takeProfit?.let { sym.formatPrice(it) } ?: "--"}",
                                        fontSize = 11.sp,
                                        color = TradingTextMuted
                                    )
                                    Text(
                                        text = "العمولة: $${String.format(Locale.US, "%.2f", trade.commission)} | سواب: $${String.format(Locale.US, "%.2f", trade.swap)}",
                                        fontSize = 10.sp,
                                        color = TradingTextMuted
                                    )
                                }

                                // Row 3: Exit Reason, R-Multiple, Duration, Timestamps
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    val reasonText = when (trade.exitReason) {
                                        ExitReason.TAKE_PROFIT -> "جني الأرباح TP"
                                        ExitReason.STOP_LOSS -> "وقف الخسارة SL"
                                        ExitReason.MANUAL_CLOSE -> "إغلاق يدوي"
                                        ExitReason.STRATEGY_CLOSE -> "إشارة استراتيجية"
                                        ExitReason.TRAILING_STOP -> "وقف متحرك"
                                        ExitReason.BREAK_EVEN -> "نقطة التعادل BE"
                                    }
                                    Text(text = "السبب: $reasonText", fontSize = 11.sp, color = TradingAccentLight)
                                    if (trade.rMultiple != 0.0) {
                                        Text(text = "R: ${String.format(Locale.US, "%.2fR", trade.rMultiple)}", fontSize = 11.sp, color = TradingGold)
                                    }
                                }

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(
                                        text = "الفتح: ${dateFormat.format(Date(trade.openTime))}",
                                        fontSize = 10.sp,
                                        color = TradingTextMuted
                                    )
                                    Text(
                                        text = "الإغلاق: ${dateFormat.format(Date(trade.closeTime))}",
                                        fontSize = 10.sp,
                                        color = TradingTextMuted
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
