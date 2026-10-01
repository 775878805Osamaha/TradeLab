package com.example.feature.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import com.example.core.model.PositionSide
import com.example.ui.theme.*
import com.example.feature.results.TradeDetailDialog
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TradingCalendarScreen(
    viewModel: TradingCalendarViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    var selectedTradeForDetail by remember { mutableStateOf<com.example.core.model.TradeJournalEntry?>(null) }

    selectedTradeForDetail?.let { trade ->
        TradeDetailDialog(trade = trade, onDismiss = { selectedTradeForDetail = null })
    }

    Scaffold(
        modifier = modifier.testTag("calendar_screen"),
        topBar = {
            TopAppBar(
                title = { Text("التقويم التداولي والملخص اليومي", fontSize = 17.sp, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
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
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            contentPadding = PaddingValues(bottom = 24.dp)
        ) {
            item {
                Text(
                    text = "ملخص الأيام التداولية (Daily Results)",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
            }

            if (uiState.dailySummaries.isEmpty()) {
                item {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = TradingCard)
                    ) {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(32.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(text = "لا توجد صفقات مغلقة في سجل التداول حتى الآن", color = TradingTextSecondary)
                        }
                    }
                }
            } else {
                items(uiState.dailySummaries.size) { index ->
                    val day = uiState.dailySummaries[index]
                    val isProfit = day.profitLoss >= 0.0

                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { viewModel.selectDate(day.fullDate) }
                            .testTag("daily_card_${day.dateStr}"),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = TradingCard),
                        border = CardDefaults.outlinedCardBorder().copy(
                            brush = androidx.compose.ui.graphics.SolidColor(
                                if (isProfit) TradingPositive.copy(alpha = 0.6f) else TradingNegative.copy(alpha = 0.6f)
                            )
                        )
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(14.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(8.dp))
                                        .background(if (isProfit) TradingPositiveBg else TradingNegativeBg)
                                        .padding(horizontal = 10.dp, vertical = 6.dp)
                                ) {
                                    Text(
                                        text = day.dateStr,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 14.sp,
                                        color = if (isProfit) TradingPositive else TradingNegative
                                    )
                                }
                                Spacer(modifier = Modifier.width(12.dp))
                                Column {
                                    Text(
                                        text = "${day.tradeCount} صفقات • ${String.format(Locale.US, "%.2f", day.totalLots)} لوت",
                                        fontSize = 12.sp,
                                        color = TradingTextSecondary
                                    )
                                    Text(
                                        text = "نسبة الفوز: ${String.format(Locale.US, "%.0f%%", day.winRatePct)}",
                                        fontSize = 11.sp,
                                        color = TradingTextMuted
                                    )
                                }
                            }

                            Text(
                                text = String.format(Locale.US, "%s$%.2f", if (isProfit) "+" else "", day.profitLoss),
                                fontSize = 17.sp,
                                fontWeight = FontWeight.ExtraBold,
                                color = if (isProfit) TradingPositive else TradingNegative
                            )
                        }
                    }
                }
            }
        }
    }

    // Modal Sheet showing trades for the selected date
    uiState.selectedDate?.let { dateStr ->
        AlertDialog(
            onDismissRequest = { viewModel.clearSelectedDate() },
            title = { Text("صفقات يوم $dateStr") },
            text = {
                LazyColumn(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(uiState.selectedDateTrades.size) { i ->
                        val t = uiState.selectedDateTrades[i]
                        val isWin = t.netProfitLoss >= 0
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(TradingElevated)
                                .clickable { selectedTradeForDetail = t }
                                .padding(10.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(text = "${t.symbol} (${if (t.side == PositionSide.BUY) "BUY" else "SELL"})", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                                Text(text = "${t.volume} lot • ${t.exitReason.name}", fontSize = 11.sp, color = TradingTextSecondary)
                            }
                            Text(
                                text = String.format(Locale.US, "%s$%.2f", if (isWin) "+" else "", t.netProfitLoss),
                                color = if (isWin) TradingPositive else TradingNegative,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { viewModel.clearSelectedDate() }) {
                    Text("إغلاق")
                }
            }
        )
    }
}
