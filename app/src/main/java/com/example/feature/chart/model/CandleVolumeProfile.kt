package com.example.feature.chart.model

import com.example.core.model.Candle

/** Distribution of actual candle volume at closing-price buckets, never tick volume-at-price. */
object CandleVolumeProfile {
    fun forDrawing(candles: List<Candle>, d: ChartDrawing, checkpoint: () -> Unit = {}): List<Bin> {
        val day=86_400_000L
        val from=if(d.tool==DrawingTool.VOLUME_PROFILE_SESSION)d.startTime/day*day else minOf(d.startTime,d.endTime?:d.startTime)
        val to=if(d.tool==DrawingTool.VOLUME_PROFILE_SESSION)from+day-1 else maxOf(d.startTime,d.endTime?:d.startTime)
        return calculate(candles,from,to,checkpoint=checkpoint)
    }
    data class Bin(val price: Double, val volume: Double)
    fun calculate(candles: List<Candle>, from: Long, to: Long, count: Int = 20, checkpoint: () -> Unit = {}): List<Bin> {
        checkpoint()
        val range=minOf(from,to)..maxOf(from,to)
        fun accepted(c: Candle)=c.openTime in range && c.close.isFinite() && c.close>0 && c.volume.isFinite() && c.volume>0
        var low=Double.POSITIVE_INFINITY;var high=Double.NEGATIVE_INFINITY;var total=0.0
        candles.forEachIndexed { index,c ->
            if(index%1024==0) checkpoint()
            if(accepted(c)) { low=minOf(low,c.close);high=maxOf(high,c.close);total+=c.volume }
        }
        if(!low.isFinite()) return emptyList()
        val n=count.coerceIn(1,100)
        if(high==low) return listOf(Bin(low,total))
        val step=(high-low)/n;val volume=DoubleArray(n)
        candles.forEachIndexed { index,c ->
            if(index%1024==0) checkpoint()
            if(accepted(c)) volume[((c.close-low)/step).toInt().coerceIn(0,n-1)]+=c.volume
        }
        checkpoint()
        return volume.indices.map { Bin(low+(it+.5)*step,volume[it]) }
    }
}
