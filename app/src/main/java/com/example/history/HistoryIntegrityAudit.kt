package com.example.history

/**
 * Pure, deterministic audit of historical OHLC bars before they enter replay/backtests.
 * Never manufactures candles to fill gaps.
 */
object HistoryIntegrityAudit {
    data class Bar(
        val openTimeMillis: Long,
        val open: Double,
        val high: Double,
        val low: Double,
        val close: Double,
        val volume: Double
    )

    enum class Problem { INVALID_PRICE, INVALID_VOLUME, DUPLICATE_TIME, OUT_OF_ORDER, MISSING_INTERVAL, FUTURE_BAR, INCOMPLETE_BAR }

    data class Finding(val index: Int, val problem: Problem, val missingBars: Long = 0)

    data class Report(
        val accepted: List<Bar>,
        val findings: List<Finding>,
        val expectedIntervalMillis: Long,
        val missingIntervals: Long
    ) {
        val clean: Boolean get() = findings.isEmpty()
    }

    /**
     * @param nowMillis fixed clock from caller for reproducible tests.
     * @param completedOnly exclude the currently forming candle from replay.
     * Duplicates and out-of-order bars are rejected rather than silently sorted.
     * Missing intervals are reported, not synthesized.
     */
    fun inspect(
        bars: List<Bar>,
        intervalMillis: Long,
        nowMillis: Long,
        completedOnly: Boolean = true
    ): Report {
        require(intervalMillis > 0) { "intervalMillis must be positive" }
        val accepted = ArrayList<Bar>(bars.size)
        val findings = ArrayList<Finding>()
        var lastTime: Long? = null
        var missing = 0L
        bars.forEachIndexed { index, bar ->
            val finite = listOf(bar.open, bar.high, bar.low, bar.close).all { it.isFinite() && it > 0.0 }
            val ohlcValid = finite &&
                bar.high >= maxOf(bar.open, bar.close, bar.low) &&
                bar.low <= minOf(bar.open, bar.close, bar.high)
            if (!ohlcValid) {
                findings += Finding(index, Problem.INVALID_PRICE)
                return@forEachIndexed
            }
            if (!bar.volume.isFinite() || bar.volume < 0.0) {
                findings += Finding(index, Problem.INVALID_VOLUME)
                return@forEachIndexed
            }
            if (bar.openTimeMillis > nowMillis) {
                findings += Finding(index, Problem.FUTURE_BAR)
                return@forEachIndexed
            }
            if (completedOnly && (bar.openTimeMillis > Long.MAX_VALUE - intervalMillis ||
                        bar.openTimeMillis + intervalMillis > nowMillis)) {
                findings += Finding(index, Problem.INCOMPLETE_BAR)
                return@forEachIndexed
            }
            val previous = lastTime
            if (previous != null) {
                if (bar.openTimeMillis == previous) {
                    findings += Finding(index, Problem.DUPLICATE_TIME)
                    return@forEachIndexed
                }
                if (bar.openTimeMillis < previous) {
                    findings += Finding(index, Problem.OUT_OF_ORDER)
                    return@forEachIndexed
                }
                val delta = bar.openTimeMillis - previous
                if (delta > intervalMillis) {
                    val count = (delta - 1) / intervalMillis
                    missing = if (Long.MAX_VALUE - missing < count) Long.MAX_VALUE else missing + count
                    findings += Finding(index, Problem.MISSING_INTERVAL, count)
                }
            }
            accepted += bar
            lastTime = bar.openTimeMillis
        }
        return Report(accepted, findings, intervalMillis, missing)
    }
}
