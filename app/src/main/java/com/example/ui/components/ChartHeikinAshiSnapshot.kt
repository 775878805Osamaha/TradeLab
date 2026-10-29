package com.example.ui.components

import com.example.core.model.Candle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Display-only transformation. Quotes, orders, indicators and source history retain raw OHLC. */
internal class ChartHeikinAshiSnapshot private constructor(
    private val source: List<Candle>, private val series: Series
) {
    class Series(val candles: List<Candle>, val priceIndex: ChartPriceRangeIndex)

    fun seriesFor(current: List<Candle>): Series? = if (current === source) series else null

    companion object {
        suspend fun prepare(source: List<Candle>): ChartHeikinAshiSnapshot = withContext(Dispatchers.Default) {
            val context = currentCoroutineContext()
            context.ensureActive()
            val converted = ArrayList<Candle>(source.size)
            source.forEachIndexed { index, raw ->
                if (index % 1024 == 0) context.ensureActive()
                val close = (raw.open + raw.high + raw.low + raw.close) / 4.0
                val open = if (index == 0) (raw.open + raw.close) / 2.0
                    else (converted.last().open + converted.last().close) / 2.0
                converted.add(raw.copy(open = open, close = close,
                    high = maxOf(raw.high, open, close), low = minOf(raw.low, open, close)))
            }
            val index = ChartPriceRangeIndex(converted) { context.ensureActive() }
            context.ensureActive()
            ChartHeikinAshiSnapshot(source, Series(converted, index))
        }
    }
}
