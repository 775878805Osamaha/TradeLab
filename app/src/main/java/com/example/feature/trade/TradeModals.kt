package com.example.feature.trade

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.ui.window.Dialog
import com.example.core.model.*
import com.example.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun OrderPreviewDialog(
    state: TradeUiState,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    val analysis = state.riskAnalysis
    val tick = state.latestTick
    val isBuy = state.orderSide == OrderSide.BUY
    val entry = if (state.orderType == OrderType.MARKET) {
        if (isBuy) (tick?.ask ?: 0.0) else (tick?.bid ?: 0.0)
    } else {
        state.requestedPrice.toDoubleOrNull() ?: 0.0
    }

    Dialog(onDismissRequest = onDismiss) {
        Card(
            modifier = Modifier.fillMaxWidth().padding(12.dp).testTag("order_preview_modal"),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = TradingCard),
            border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
        ) {
            Column(
                modifier = Modifier.padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(text = "معاينة الأمر الافتراضي قبل التنفيذ", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "إغلاق")
                    }
                }

                HorizontalDivider(color = TradingBorder)

                PreviewRow("الأداة المالية", state.selectedSymbol)
                PreviewRow("نوع الأمر", "${state.orderType.name} (${state.orderSide.displayNameAr})", isAccent = true)
                PreviewRow("حجم العقد", "${state.volume} لوت")
                PreviewRow("سعر الدخول المقترح", String.format(Locale.US, "%.4f", entry))

                if (state.stopLoss.isNotBlank()) {
                    PreviewRow("وقف الخسارة (SL)", state.stopLoss, color = TradingNegative)
                }
                if (state.takeProfit.isNotBlank()) {
                    PreviewRow("جني الأرباح (TP)", state.takeProfit, color = TradingPositive)
                }

                analysis?.let { a ->
                    HorizontalDivider(color = TradingBorder)
                    PreviewRow("الهامش المطلوب", String.format(Locale.US, "$%.2f", a.requiredMargin))
                    PreviewRow("الخسارة المحتملة", String.format(Locale.US, "$%.2f (%.1f%%)", a.potentialLoss, a.riskPercentage), color = TradingNegative)
                    if (a.potentialProfit > 0.0) {
                        PreviewRow("الربح المتوقع", String.format(Locale.US, "$%.2f", a.potentialProfit), color = TradingPositive)
                    }
                    a.riskRewardRatio?.let { rrr ->
                        PreviewRow("نسبة العائد إلى المخاطرة", String.format(Locale.US, "1:%.2f", rrr), color = TradingGold)
                    }
                    PreviewRow("الهامش المتاح بعد التنفيذ", String.format(Locale.US, "$%.2f", a.freeMarginRemaining))
                }

                Spacer(modifier = Modifier.height(6.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("تعديل")
                    }
                    Button(
                        onClick = onConfirm,
                        modifier = Modifier.weight(1.5f).testTag("confirm_order_preview_btn"),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (isBuy) TradingPositive else TradingNegative
                        )
                    ) {
                        Text("تأكيد التنفيذ الافتراضي", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
fun PositionDetailsModal(
    position: Position,
    currentTick: Tick?,
    onClose: () -> Unit,
    onPartialClose: () -> Unit,
    onBreakEven: () -> Unit,
    onModify: () -> Unit,
    onDismiss: () -> Unit
) {
    val sdf = remember { SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.US) }
    val isBuy = position.side == PositionSide.BUY
    val currPrice = if (isBuy) (currentTick?.bid ?: position.currentPrice) else (currentTick?.ask ?: position.currentPrice)
    val isProfit = position.profitLoss >= 0

    Dialog(onDismissRequest = onDismiss) {
        Card(
            modifier = Modifier.fillMaxWidth().padding(12.dp).testTag("position_details_modal"),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = TradingCard),
            border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
        ) {
            Column(
                modifier = Modifier.padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(text = "تفاصيل الصفقة #${position.id}", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                        Text(text = "${position.symbol} • ${if (isBuy) "شراء BUY" else "بيع SELL"} ${position.volume} لوت", fontSize = 12.sp, color = TradingTextSecondary)
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "إغلاق")
                    }
                }

                HorizontalDivider(color = TradingBorder)

                PreviewRow("سعر الدخول", String.format(Locale.US, "%.4f", position.entryPrice))
                PreviewRow("السعر الحالي", String.format(Locale.US, "%.4f", currPrice))
                PreviewRow(
                    "الربح/الخسارة اللحظية",
                    String.format(Locale.US, "%s$%.2f", if (isProfit) "+" else "", position.profitLoss),
                    color = if (isProfit) TradingPositive else TradingNegative
                )
                PreviewRow("الهامش المحجوز", String.format(Locale.US, "$%.2f", position.margin))
                PreviewRow("وقف الخسارة (SL)", position.stopLoss?.let { String.format(Locale.US, "%.4f", it) } ?: "غير محدد")
                PreviewRow("جني الأرباح (TP)", position.takeProfit?.let { String.format(Locale.US, "%.4f", it) } ?: "غير محدد")
                PreviewRow("وقت الفتح", sdf.format(Date(position.openTime)))

                Spacer(modifier = Modifier.height(6.dp))

                // Actions Grid
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Button(
                        onClick = onBreakEven,
                        modifier = Modifier.weight(1f).testTag("pos_modal_be_btn"),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingAccent),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Text("التعادل", fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                    Button(
                        onClick = onModify,
                        modifier = Modifier.weight(1f).testTag("pos_modal_modify_btn"),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingElevated),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Text("تعديل", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TradingCyan)
                    }
                    Button(
                        onClick = onPartialClose,
                        modifier = Modifier.weight(1f).testTag("pos_modal_partial_btn"),
                        colors = ButtonDefaults.buttonColors(containerColor = TradingElevated),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Text("إغلاق جزئي", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = TradingGold)
                    }
                }

                Button(
                    onClick = onClose,
                    modifier = Modifier.fillMaxWidth().testTag("pos_modal_close_btn"),
                    colors = ButtonDefaults.buttonColors(containerColor = TradingNegative),
                    shape = RoundedCornerShape(8.dp)
                ) {
                    Text("إغلاق الصفقة كاملة الآن", fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun PreviewRow(
    label: String,
    value: String,
    isAccent: Boolean = false,
    color: Color = TradingTextPrimary
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = label, fontSize = 12.sp, color = TradingTextSecondary)
        Text(
            text = value,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isAccent) TradingAccentLight else color
        )
    }
}
