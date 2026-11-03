package com.example.feature.replay

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.core.market.VerifiedMarketQuote
import com.example.feature.chart.history.ChartHistoryPaging
import java.io.IOException

/**
 * Prior market bars are for chart inspection only, never for the ReplayDataView.
 * The strict boundary is the first candle in the independent replay engine.
 */
object ReplayChartLookback {
    fun prepend(
        existing: List<Candle>,
        incoming: List<Candle>,
        replayFirstOpen: Long,
        symbol: String,
        timeframe: Timeframe
    ): List<Candle> {
        if (incoming.isEmpty()) return existing
        val expectedSource = if (symbol in VerifiedMarketQuote.forexSymbols)
            "CTRADER_HISTORICAL" else "BINANCE_HISTORICAL"
        if (incoming.any { bar ->
                bar.symbol != symbol || bar.timeframe != timeframe ||
                    bar.source != expectedSource || bar.openTime >= replayFirstOpen
            } || incoming.zipWithNext().any { (a,b) -> a.openTime >= b.openTime }) {
            throw IOException("مصدر الشموع الأقدم غير صحيح أو تجاوز حد Replay الآمن")
        }
        if (existing.any { it.symbol!=symbol || it.timeframe!=timeframe ||
                it.source!=expectedSource || it.openTime>=replayFirstOpen }) {
            throw IOException("تاريخ الشارت المحلي لا يطابق حساب Replay")
        }
        val merged = ChartHistoryPaging.merge(existing,incoming)
        if (merged.zipWithNext().any { (a,b) -> a.openTime >= b.openTime })
            throw IOException("شموع قديمة مكررة أو غير مرتبة")
        return merged
    }
}
