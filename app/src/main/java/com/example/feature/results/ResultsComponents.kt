package com.example.feature.results

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.example.core.export.ResultsExporter
import com.example.core.model.*
import com.example.ui.theme.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun TradeDetailDialog(
    trade: TradeJournalEntry,
    onDismiss: () -> Unit
) {
    val sdf = remember { SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US) }
    val sym = remember(trade.symbol) { com.example.core.market.DefaultSymbols.getSymbol(trade.symbol) }
    val riskAmount = trade.stopLoss?.let {
        kotlin.math.abs(trade.entryPrice - it) * trade.volume * sym.contractSize
    }

    Dialog(onDismissRequest = onDismiss) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = TradingCard),
            border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
        ) {
            Column(
                modifier = Modifier
                    .padding(20.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(text = "تفاصيل الصفقة #${trade.id}", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        Text(text = "المصدر: ${trade.mode}", fontSize = 11.sp, color = TradingTextSecondary)
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "إغلاق")
                    }
                }

                HorizontalDivider(color = TradingBorder)

                // Direction & Net P/L
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (trade.side == PositionSide.BUY) TradingPositive.copy(alpha = 0.2f) else TradingNegative.copy(alpha = 0.2f))
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) {
                        Text(
                            text = if (trade.side == PositionSide.BUY) "شراء (BUY)" else "بيع (SELL)",
                            color = if (trade.side == PositionSide.BUY) TradingPositive else TradingNegative,
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp
                        )
                    }

                    Text(
                        text = v3Money(trade.netProfitLoss,true),
                        style = TextStyle(textDirection=TextDirection.Ltr),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (trade.netProfitLoss >= 0) TradingPositive else TradingNegative
                    )
                }

                // Attributes List
                DetailRow("رمز الأداة", trade.symbol)
                DetailRow("حجم العقد (Volume)", "${trade.volume} Lot")
                DetailRow("سعر الدخول", String.format(Locale.US, "%.${sym.digits}f", trade.entryPrice))
                DetailRow("سعر الخروج", String.format(Locale.US, "%.${sym.digits}f", trade.exitPrice))
                DetailRow("وقف الخسارة (SL)", trade.stopLoss?.let { String.format(Locale.US, "%.${sym.digits}f", it) } ?: "غير محدد")
                DetailRow("جني الأرباح (TP)", trade.takeProfit?.let { String.format(Locale.US, "%.${sym.digits}f", it) } ?: "غير محدد")
                DetailRow("الربح الإجمالي (Gross)", v3Money(trade.profitLoss,true))
                DetailRow("العمولة (Commission)", v3Money(-trade.commission))
                DetailRow("رسوم التبييت (Swap)", v3Money(trade.swap,true))
                DetailRow("مبلغ المخاطرة (Risk)", riskAmount?.let { v3Money(it) } ?: "—")
                DetailRow("المضاعف R (R-Multiple)", if(riskAmount!=null && riskAmount>0)String.format(Locale.US, "%.2f R", trade.rMultiple) else "—")
                DetailRow("السبريد", "مضمن في أسعار التنفيذ؛ لا يُخصم مرة أخرى")
                DetailRow("سبب الخروج", when(trade.exitReason) {
                    ExitReason.TAKE_PROFIT->"جني الربح"
                    ExitReason.STOP_LOSS->"وقف الخسارة"
                    ExitReason.MANUAL_CLOSE->"إغلاق يدوي"
                    ExitReason.STRATEGY_CLOSE->"إغلاق الاستراتيجية"
                    ExitReason.TRAILING_STOP->"وقف متحرك"
                    ExitReason.BREAK_EVEN->"تعادل"
                })
                DetailRow("الاستراتيجية", trade.strategyId ?: "يدوي (Manual)")
                DetailRow("وقت الفتح", sdf.format(Date(trade.openTime)))
                DetailRow("وقت الإغلاق", sdf.format(Date(trade.closeTime)))
                DetailRow("مدة الصفقة", "${trade.durationMillis / 1000} ثانية (${trade.durationMillis / 60000} دقيقة)")

                Spacer(modifier = Modifier.height(6.dp))

                Button(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = TradingElevated)
                ) {
                    Text("إغلاق", color = TradingTextPrimary)
                }
            }
        }
    }
}

@Composable
fun RunComparisonDialog(
    runs: List<BacktestRun>,
    onDismiss: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = TradingCard),
            border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
        ) {
            Column(
                modifier = Modifier
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(text = "مقارنة نتائج الاختبارات التاريخية (${runs.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "إغلاق")
                    }
                }

                Text(
                    text = "عرض مقارن محايد للمعاملات المقاسة جنباً إلى جنب دون تصنيف أو تفضيل.",
                    fontSize = 11.sp,
                    color = TradingTextMuted
                )

                HorizontalDivider(color = TradingBorder)

                // Comparison Table
                ComparisonRow("الاستراتيجية", runs.map { it.strategyName })
                ComparisonRow("الأصل والإطار", runs.map { "${it.symbol} • ${it.timeframe.displayName}" })
                ComparisonRow("صافي الربح", runs.map { String.format(Locale.US, "%s$%.2f", if (it.netProfit >= 0) "+" else "", it.netProfit) })
                ComparisonRow("العائد %", runs.map { String.format(Locale.US, "%.1f%%", it.returnPercentage) })
                ComparisonRow("عامل الربح (PF)", runs.map { it.profitFactor?.let { v -> String.format(Locale.US, "%.2f", v) } ?: "N/A" })
                ComparisonRow("معدل الفوز", runs.map { String.format(Locale.US, "%.1f%%", it.winRate) })
                ComparisonRow("أقصى تراجع %", runs.map { String.format(Locale.US, "%.1f%%", it.maxDrawdownPercentage) })
                ComparisonRow("إجمالي الصفقات", runs.map { "${it.totalTrades}" })
                ComparisonRow("التوقع الرياضي", runs.map { it.expectancy?.let { e -> String.format(Locale.US, "$%.2f", e) } ?: "N/A" })

                Spacer(modifier = Modifier.height(10.dp))

                Button(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = TradingElevated)
                ) {
                    Text("إغلاق المقارنة", color = TradingTextPrimary)
                }
            }
        }
    }
}

@Composable
fun ExportDialog(
    metrics: PerformanceMetrics,
    trades: List<TradeJournalEntry>,
    dailySummaries: List<DailySummary>,
    points: List<EquityPoint>,
    onDismiss: () -> Unit
) {
    var exportFormat by remember { mutableStateOf("CSV_SUMMARY") }
    val clipboardManager = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }

    val exportedText = remember(exportFormat, metrics, trades, dailySummaries, points) {
        when (exportFormat) {
            "CSV_SUMMARY" -> ResultsExporter.exportSummaryCsv(metrics)
            "CSV_TRADES" -> ResultsExporter.exportTradesCsv(trades)
            "CSV_DAILY" -> ResultsExporter.exportDailyResultsCsv(dailySummaries)
            "CSV_EQUITY" -> ResultsExporter.exportEquityPointsCsv(points)
            "JSON" -> ResultsExporter.exportCompleteJson(metrics, trades, dailySummaries, points)
            else -> ""
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = TradingCard),
            border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
        ) {
            Column(
                modifier = Modifier
                    .padding(18.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.FileDownload, contentDescription = null, tint = TradingAccent)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(text = "تصدير نتائج التحليلات", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "إغلاق")
                    }
                }

                HorizontalDivider(color = TradingBorder)

                // Export format selectors
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    ExportOption("ملخص الإحصاءات (CSV Summary)", exportFormat == "CSV_SUMMARY") { exportFormat = "CSV_SUMMARY" }
                    ExportOption("سجل الصفقات (CSV Trades)", exportFormat == "CSV_TRADES") { exportFormat = "CSV_TRADES" }
                    ExportOption("النتائج اليومية (CSV Daily)", exportFormat == "CSV_DAILY") { exportFormat = "CSV_DAILY" }
                    ExportOption("منحنى رأس المال (CSV Equity Points)", exportFormat == "CSV_EQUITY") { exportFormat = "CSV_EQUITY" }
                    ExportOption("ملف متكامل (JSON Complete)", exportFormat == "JSON") { exportFormat = "JSON" }
                }

                // Preview Card
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(130.dp),
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingElevated)
                ) {
                    Text(
                        text = exportedText.take(450) + if (exportedText.length > 450) "\n..." else "",
                        modifier = Modifier.padding(10.dp),
                        fontSize = 10.sp,
                        color = TradingTextSecondary,
                        lineHeight = 14.sp
                    )
                }

                // Copy to Clipboard Button
                Button(
                    onClick = {
                        clipboardManager.setText(AnnotatedString(exportedText))
                        copied = true
                    },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = TradingAccent)
                ) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(if (copied) "تم النسخ بنجاح!" else "نسخ البيانات للحافظة")
                }
            }
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = label, fontSize = 12.sp, color = TradingTextSecondary, modifier=Modifier.weight(1f).padding(end=8.dp))
        Text(text = value, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = TradingTextPrimary, style = TextStyle(textDirection=TextDirection.ContentOrLtr), modifier=Modifier.weight(1f), textAlign=androidx.compose.ui.text.style.TextAlign.End)
    }
}

@Composable
private fun ComparisonRow(label: String, values: List<String>) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Text(text = label, fontSize = 11.sp, color = TradingTextMuted, fontWeight = FontWeight.Bold)
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            values.forEach { v ->
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(6.dp))
                        .background(TradingElevated)
                        .padding(horizontal = 6.dp, vertical = 4.dp)
                ) {
                    Text(text = v, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = TradingTextPrimary)
                }
            }
        }
    }
}

@Composable
private fun ExportOption(title: String, isSelected: Boolean, onSelect: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(6.dp))
            .background(if (isSelected) TradingElevated else Color.Transparent)
            .clickable(onClick = onSelect)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        RadioButton(selected = isSelected, onClick = onSelect)
        Spacer(modifier = Modifier.width(6.dp))
        Text(text = title, fontSize = 12.sp, fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal)
    }
}
