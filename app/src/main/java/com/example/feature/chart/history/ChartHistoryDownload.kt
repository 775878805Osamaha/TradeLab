package com.example.feature.chart.history

import com.example.core.model.Candle
import com.example.core.market.HistoricalCandleIntegrity
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.delay

/** Downloads real provider pages; a target is never padded with generated bars. */
object ChartHistoryDownload {
    const val TARGET = 100_001
    enum class Result { TARGET_REACHED, NO_OLDER_PAGE }

    suspend fun run(
        initial: List<Candle>,
        target: Int = TARGET,
        pauseMillis: Long = 250L,
        fetchBefore: suspend (Long) -> List<Candle>,
        append: suspend (List<Candle>) -> Unit
    ): Result {
        require(initial.isNotEmpty() && target > 0 && pauseMillis >= 0)
        currentCoroutineContext().ensureActive()
        val symbol = initial.first().symbol
        val timeframe = initial.first().timeframe
        var oldest = initial.first().openTime
        var count = initial.size
        while (count < target) {
            currentCoroutineContext().ensureActive()
            val page = fetchBefore(oldest)
            currentCoroutineContext().ensureActive()
            if (page.isEmpty()) return Result.NO_OLDER_PAGE
            require(page.all { it.symbol == symbol && it.timeframe == timeframe && it.openTime < oldest } &&
                page.zipWithNext().all { (a,b) -> a.openTime < b.openTime }) { "Older page did not advance history" }
            HistoricalCandleIntegrity.validate(page, 0, oldest, expectedSymbol=symbol, expectedTimeframe=timeframe)
            currentCoroutineContext().ensureActive()
            append(page)
            currentCoroutineContext().ensureActive()
            count += page.size
            oldest = page.first().openTime
            if (count < target) delay(pauseMillis)
        }
        return Result.TARGET_REACHED
    }
}
