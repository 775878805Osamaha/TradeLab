package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CheckCircleOutline
import androidx.compose.material.icons.outlined.Save
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.feature.chart.model.IndicatorSettings

/** Presets only change indicator visibility, never market candles or replay data. */
internal object IndicatorTemplates {
    fun priceOnly(current: IndicatorSettings) = current.copy(
        isSmaEnabled = false, isEmaEnabled = false, isBollingerEnabled = false,
        isVwapEnabled = false, isRsiEnabled = false, isMacdEnabled = false, isAtrEnabled = false
    )

    fun trend(current: IndicatorSettings) = priceOnly(current).copy(
        isSmaEnabled = true, isEmaEnabled = true, isVwapEnabled = true
    )

    fun volatility(current: IndicatorSettings) = priceOnly(current).copy(
        isBollingerEnabled = true, isRsiEnabled = true, isAtrEnabled = true
    )

    fun momentum(current: IndicatorSettings) = priceOnly(current).copy(
        isEmaEnabled = true, isRsiEnabled = true, isMacdEnabled = true
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun IndicatorTemplatesSheet(
    current: IndicatorSettings,
    savedTemplate: IndicatorSettings?,
    onApply: (IndicatorSettings) -> Unit,
    onSaveCurrent: () -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Color.White,
        contentColor = Color(0xFF171717),
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).testTag("indicator_templates_sheet")) {
            Text("قوالب المؤشر", fontSize = 25.sp, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Right, modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp))
            Text("اختر مجموعة جاهزة أو احفظ إعدادات مؤشراتك الحالية.",
                color = Color(0xFF666666), fontSize = 14.sp, textAlign = TextAlign.Right,
                modifier = Modifier.fillMaxWidth().padding(bottom = 15.dp))
            val templates = listOf(
                Triple("price", "السعر فقط", IndicatorTemplates.priceOnly(current)),
                Triple("trend", "اتجاه السوق · SMA / EMA / VWAP", IndicatorTemplates.trend(current)),
                Triple("volatility", "التذبذب · BB / RSI / ATR", IndicatorTemplates.volatility(current)),
                Triple("momentum", "الزخم · EMA / RSI / MACD", IndicatorTemplates.momentum(current))
            )
            templates.forEach { (id, title, settings) ->
                TemplateRow(title, isSelected = current == settings,
                    modifier = Modifier.testTag("indicator_template_$id")) { onApply(settings) }
                Spacer(Modifier.height(7.dp))
            }
            if (savedTemplate != null) {
                TemplateRow("قالبي المحفوظ", isSelected = current == savedTemplate,
                    modifier = Modifier.testTag("indicator_template_saved")) { onApply(savedTemplate) }
                Spacer(Modifier.height(7.dp))
            }
            OutlinedButton(onClick = onSaveCurrent, modifier = Modifier.fillMaxWidth()
                .testTag("indicator_template_save")) {
                Icon(Icons.Outlined.Save, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text(if (savedTemplate == null) "حفظ الإعدادات الحالية كقالب" else "تحديث قالبي المحفوظ")
            }
            Spacer(Modifier.height(22.dp))
        }
    }
}

@Composable
private fun TemplateRow(title: String, isSelected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Row(
        modifier.fillMaxWidth().background(Color(0xFFF2F2F2), RoundedCornerShape(14.dp))
            .clickable(onClick = onClick).padding(horizontal = 15.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Icon(if (isSelected) Icons.Outlined.CheckCircleOutline else Icons.Outlined.BookmarkBorder,
            contentDescription = null, tint = if (isSelected) Color(0xFF2768D8) else Color(0xFF888888))
        Spacer(Modifier.width(10.dp))
        Text(title, modifier = Modifier.weight(1f), fontSize = 14.sp, fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Right)
    }
}
