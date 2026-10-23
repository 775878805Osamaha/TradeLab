package com.example.feature.chart

/** Presentation-only rules. Never substitute synthetic bars for missing provider data. */
object ChartDisplayRules {
    fun showNoData(isLoading: Boolean, candleCount: Int): Boolean =
        !isLoading && candleCount == 0

    /** DatePicker returns UTC midnight; preserve the selected date as an instant. */
    fun selectedReplayTimestamp(selectedDateMillis: Long?, isLoading: Boolean, candleCount: Int): Long? =
        selectedDateMillis?.takeIf { it >= 0L && !isLoading && candleCount > 0 }
}
