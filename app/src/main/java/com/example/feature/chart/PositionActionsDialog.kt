package com.example.feature.chart

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import com.example.core.model.Position
import com.example.core.model.PositionSide
import com.example.core.model.Tick

/** Actions always target the selected account's position, never a copied order. */
@Composable
fun PositionActionsDialog(
    position: Position,
    tick: Tick?,
    onDismiss: () -> Unit,
    onClose: (Double?) -> Unit,
    onProtection: (Double?, Double?) -> Unit
) {
    var mode by remember(position.id) { mutableStateOf("menu") }
    var value by remember(position.id, mode) { mutableStateOf("") }
    val number = value.toDoubleOrNull()?.takeIf { it.isFinite() && it > 0 }
    val price = tick?.takeIf { it.symbol == position.symbol }?.let {
        if (position.side == PositionSide.BUY) it.bid else it.ask
    }
    val valid = when (mode) {
        "partial" -> validPartialClose(position.symbol, position.volume, number)
        "sl" -> number != null && price != null &&
            if (position.side == PositionSide.BUY) number < price else number > price
        "tp" -> number != null && price != null &&
            if (position.side == PositionSide.BUY) number > price else number < price
        else -> false
    }
    AlertDialog(
        modifier = Modifier.testTag("chart_position_actions"),
        onDismissRequest = onDismiss,
        title = { Text("${position.symbol} · #${position.id}") },
        text = {
            Column {
                Text("الحجم المفتوح: ${position.volume} لوت")
                if (mode == "menu") {
                    TextButton(onClick = { mode = "close" }, modifier = Modifier.testTag("position_close")) { Text("إغلاق الصفقة") }
                    TextButton(onClick = { mode = "sl" }, modifier = Modifier.testTag("position_sl")) { Text("وضع وقف الخسارة") }
                    TextButton(onClick = { mode = "tp" }, modifier = Modifier.testTag("position_tp")) { Text("وضع الهدف") }
                    TextButton(onClick = { mode = "partial" }, modifier = Modifier.testTag("position_partial")) { Text("حجز جزء من الصفقة — إغلاق جزئي") }
                } else if (mode == "close") {
                    Text("تأكيد إغلاق الصفقة بالكامل بالسعر المتاح؟")
                } else {
                    OutlinedTextField(
                        value = value, onValueChange = { value = it },
                        label = { Text(when (mode) { "sl" -> "سعر وقف الخسارة"; "tp" -> "سعر الهدف"; else -> "الحجم المراد إغلاقه باللوت" }) },
                        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        isError = value.isNotBlank() && !valid,
                        modifier = Modifier.testTag("position_action_value")
                    )
                    if (value.isNotBlank() && !valid) Text("تحقق من القيمة واتجاه الصفقة والحجم المتبقي")
                }
            }
        },
        confirmButton = {
            if (mode != "menu") TextButton(
                enabled = mode == "close" || valid,
                modifier = Modifier.testTag("position_action_confirm"),
                onClick = {
                    when (mode) {
                        "close" -> onClose(null)
                        "partial" -> onClose(number)
                        "sl" -> onProtection(number, position.takeProfit)
                        "tp" -> onProtection(position.stopLoss, number)
                    }
                }
            ) { Text("تأكيد") }
        },
        dismissButton = { TextButton(onClick = { if (mode == "menu") onDismiss() else mode = "menu" }) { Text(if (mode == "menu") "إلغاء" else "رجوع") } }
    )
}

internal fun validPartialClose(symbol: String, openVolume: Double, amount: Double?): Boolean {
    if (amount == null || !amount.isFinite() || amount <= 0.0 || amount >= openVolume) return false
    val spec = com.example.core.market.DefaultSymbols.getSymbol(symbol)
    val remaining = openVolume - amount
    return amount + 1e-9 >= spec.minLot && remaining + 1e-9 >= spec.minLot &&
        listOf(amount, remaining).all { kotlin.math.abs(it / spec.lotStep - kotlin.math.round(it / spec.lotStep)) <= 1e-6 }
}
