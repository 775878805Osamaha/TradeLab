package com.example.feature.chart.model

import androidx.compose.ui.graphics.Color
import com.example.ui.theme.*

enum class ChartIndicatorType(val displayNameAr: String, val isOverlay: Boolean) {
    SMA("المتوسط البسيط (SMA)", true),
    EMA("المتوسط الأسي (EMA)", true),
    BOLLINGER("نطاقات بولينجر (BB)", true),
    VWAP("متوسط السعر المرجح (VWAP)", true),
    RSI("مؤشر القوة النسبية (RSI)", false),
    MACD("مؤشر الماكد (MACD)", false),
    ATR("متوسط المدى الحقيقي (ATR)", false)
}

data class IndicatorSettings(
    val smaPeriod: Int = 20,
    val isSmaEnabled: Boolean = false,
    val emaPeriod: Int = 20,
    val isEmaEnabled: Boolean = true,
    val bollingerPeriod: Int = 20,
    val bollingerStdDev: Double = 2.0,
    val isBollingerEnabled: Boolean = false,
    val isVwapEnabled: Boolean = false,
    val rsiPeriod: Int = 14,
    val isRsiEnabled: Boolean = false,
    val macdFast: Int = 12,
    val macdSlow: Int = 26,
    val macdSignal: Int = 9,
    val isMacdEnabled: Boolean = false,
    val atrPeriod: Int = 14,
    val isAtrEnabled: Boolean = false
) {
    val hasSubpanelIndicators: Boolean
        get() = isRsiEnabled || isMacdEnabled || isAtrEnabled
}
