package com.example.feature.chart.model

import com.example.core.model.Candle

/** Distribution of actual candle volume at closing-price buckets, never tick volume-at-price. */
object CandleVolumeProfile {
    fun forDrawing(candles: List<Candle>, d: ChartDrawing): List<Bin> {
        val day=86_400_000L
        val from=if(d.tool==DrawingTool.VOLUME_PROFILE_SESSION)d.startTime/day*day else minOf(d.startTime,d.endTime?:d.startTime)
        val to=if(d.tool==DrawingTool.VOLUME_PROFILE_SESSION)from+day-1 else maxOf(d.startTime,d.endTime?:d.startTime)
        return calculate(candles,from,to)
    }
    data class Bin(val price: Double, val volume: Double)
    fun calculate(candles: List<Candle>, from: Long, to: Long, count: Int = 20): List<Bin> {
        val source = candles.filter { it.openTime in minOf(from,to)..maxOf(from,to) && it.close.isFinite() && it.close>0 && it.volume.isFinite() && it.volume>0 }
        if(source.isEmpty()) return emptyList()
        val low=source.minOf{it.close};val high=source.maxOf{it.close};val n=count.coerceIn(1,100)
        if(high==low) return listOf(Bin(low,source.sumOf{it.volume}))
        val step=(high-low)/n;val volume=DoubleArray(n)
        source.forEach { volume[((it.close-low)/step).toInt().coerceIn(0,n-1)]+=it.volume }
        return volume.indices.map { Bin(low+(it+.5)*step,volume[it]) }
    }
}
