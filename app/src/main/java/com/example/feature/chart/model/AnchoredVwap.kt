package com.example.feature.chart.model

import com.example.core.model.Candle

data class VwapPoint(val time: Long, val price: Double)
object AnchoredVwap {
    fun calculate(candles: List<Candle>, start: Long): List<VwapPoint> {
        if (candles.isEmpty() || candles.first().openTime > start) return emptyList()
        var volume = 0.0
        var weighted = 0.0
        return buildList {
            candles.forEach { candle ->
                if(candle.openTime >= start && candle.volume.isFinite() && candle.volume > 0 &&
                    candle.high.isFinite() && candle.low.isFinite() && candle.close.isFinite()) {
                    volume += candle.volume
                    weighted += ((candle.high + candle.low + candle.close) / 3) * candle.volume
                    val value = weighted / volume
                    if(value.isFinite() && value > 0) add(VwapPoint(candle.openTime, value))
                }
            }
        }
    }
}
