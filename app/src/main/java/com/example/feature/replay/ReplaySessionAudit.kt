package com.example.feature.replay

import com.example.core.model.Candle
import java.util.Locale

/** Validates only candles already revealed to the user. Never reads future bars. */
data class ReplayDataAudit(
    val candleCount: Int,
    val firstOpenTime: Long?,
    val lastOpenTime: Long?,
    val invalidPrices: Int,
    val invalidRanges: Int,
    val duplicateOrOutOfOrder: Int,
    val intervalGaps: Int,
    val missingBars: Long,
    val volumeAnomalies: Int
) {
    val isClean: Boolean get() =
        invalidPrices == 0 && invalidRanges == 0 && duplicateOrOutOfOrder == 0 &&
            intervalGaps == 0 && volumeAnomalies == 0
}

object ReplaySessionAudit {
    fun inspect(candles: List<Candle>, intervalMinutes: Int): ReplayDataAudit {
        require(intervalMinutes > 0)
        val interval = intervalMinutes.toLong() * 60_000L
        var invalidPrices = 0
        var invalidRanges = 0
        var duplicate = 0
        var gaps = 0
        var missing = 0L
        var volumeAnomalies = 0
        var previous: Candle? = null
        candles.forEach { candle ->
            val prices = listOf(candle.open, candle.high, candle.low, candle.close)
            if (prices.any { !it.isFinite() || it <= 0.0 }) invalidPrices++
            else if (candle.high < candle.low ||
                candle.high < maxOf(candle.open, candle.close) ||
                candle.low > minOf(candle.open, candle.close)) invalidRanges++
            if (!candle.volume.isFinite() || candle.volume < 0.0) volumeAnomalies++
            previous?.let { prev ->
                val delta = candle.openTime - prev.openTime
                if (delta <= 0L || delta % interval != 0L) duplicate++
                else if (delta > interval) {
                    gaps++
                    missing += delta / interval - 1L
                }
            }
            previous = candle
        }
        return ReplayDataAudit(
            candleCount = candles.size,
            firstOpenTime = candles.firstOrNull()?.openTime,
            lastOpenTime = candles.lastOrNull()?.openTime,
            invalidPrices = invalidPrices,
            invalidRanges = invalidRanges,
            duplicateOrOutOfOrder = duplicate,
            intervalGaps = gaps,
            missingBars = missing,
            volumeAnomalies = volumeAnomalies
        )
    }

    fun exportCsv(audit: ReplayDataAudit, symbol: String, timeframe: String): String = buildString {
        appendLine("metric,value")
        appendLine("symbol,${csvSafe(symbol)}")
        appendLine("timeframe,${csvSafe(timeframe)}")
        appendLine("revealed_candles,${audit.candleCount}")
        appendLine("first_open_timestamp_ms,${audit.firstOpenTime ?: ""}")
        appendLine("last_open_timestamp_ms,${audit.lastOpenTime ?: ""}")
        appendLine("invalid_prices,${audit.invalidPrices}")
        appendLine("invalid_ohlc_ranges,${audit.invalidRanges}")
        appendLine("out_of_order_or_misaligned,${audit.duplicateOrOutOfOrder}")
        appendLine("interval_gaps,${audit.intervalGaps}")
        appendLine("estimated_missing_bars,${audit.missingBars}")
        appendLine("invalid_volumes,${audit.volumeAnomalies}")
        appendLine("audit_clean,${audit.isClean}")
    }

    private fun csvSafe(input: String): String = "\"" +
        input.replace("\"", "\"\"").replace("\n", " ").replace("\r", " ") + "\""
}
