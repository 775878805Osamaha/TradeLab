package com.example.core.market

import com.example.core.model.Candle

/** Independent free sources; transport outages must never masquerade as empty history. */
object FreeChartHistory {
    suspend fun load(
        cachedAlternative: suspend () -> List<Candle>?,
        primary: suspend () -> List<Candle>,
        alternative: (suspend () -> List<Candle>)?
    ): List<Candle> {
        cachedAlternative()?.let { return it }
        val candles=try { primary() }
        catch(error: MarketDataRequestException) {
            val transient=error.message?.let {
                it.contains("network failure") || it.contains("HTTP 503") || it.contains("انتهت مهلة")
            }==true
            if(!transient || alternative==null) throw error
            return alternative()
        }
        return if(candles.isEmpty() && alternative!=null) alternative() else candles
    }
}
