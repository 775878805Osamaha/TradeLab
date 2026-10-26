package com.example.feature.trade

import com.example.core.model.Candle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal data class TradeCandleResult(
    val candles: List<Candle> = emptyList(),
    val message: String? = null
)

/** Keep provider failures recoverable without reviving a cancelled symbol request. */
internal suspend fun loadTradeCandles(
    symbol: String,
    fetch: suspend () -> List<Candle>
): TradeCandleResult {
    currentCoroutineContext().ensureActive()
    // Capability and integrity belong to the repository/provider. Gold/FX
    // have a real historical provider; do not reject them before fetching.
    return try {
        val candles = fetch()
        // A provider/cache may return after cancellation. Never publish that result.
        currentCoroutineContext().ensureActive()
        if (candles.isEmpty()) {
            TradeCandleResult(message = "لم يُرجع مصدر السوق أي شموع موثوقة للرمز $symbol. يمكنك إعادة المحاولة.")
        } else {
            TradeCandleResult(candles)
        }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        currentCoroutineContext().ensureActive()
        val detail = (error.cause?.message ?: error.message ?: "سبب غير معروف").take(180)
        TradeCandleResult(message = "تعذر تحميل بيانات $symbol: ${error.javaClass.simpleName}: $detail")
    }
}
