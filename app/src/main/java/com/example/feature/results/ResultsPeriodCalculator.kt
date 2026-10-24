package com.example.feature.results

import com.example.core.model.TradeJournalEntry
import com.example.core.model.EquityPoint
import com.example.core.model.PerformanceMetrics
import com.example.core.statistics.StatisticsCalculator
import java.util.Calendar

enum class ResultsPeriod(val titleAr: String) {
    ALL("الكل"), MONTH("شهر"), WEEK("أسبوع")
}

data class ResultsPeriodSnapshot(
    val openingBalance: Double,
    val closingBalance: Double,
    val trades: List<TradeJournalEntry>,
    val metrics: PerformanceMetrics,
    val curve: List<EquityPoint>
)

/** The selected period has its own opening balance, not the account's original deposit. */
object ResultsPeriodCalculator {
    fun cutoff(period: ResultsPeriod, now: Long): Long? {
        if (period == ResultsPeriod.ALL) return null
        val calendar = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (period == ResultsPeriod.MONTH) {
                set(Calendar.DAY_OF_MONTH, 1)
            } else {
                firstDayOfWeek = Calendar.SATURDAY
                set(Calendar.DAY_OF_WEEK, firstDayOfWeek)
            }
        }
        return calendar.timeInMillis
    }

    fun calculate(
        initialBalance: Double,
        trades: List<TradeJournalEntry>,
        period: ResultsPeriod,
        now: Long
    ): ResultsPeriodSnapshot {
        require(initialBalance.isFinite()) { "Invalid opening account balance" }
        require(now >= 0L) { "Invalid report timestamp" }
        require(trades.all {
            it.closeTime >= it.openTime &&
                it.netProfitLoss.isFinite() &&
                it.volume.isFinite() && it.volume > 0.0
        }) { "Invalid trade in period report" }
        // Future-dated trades cannot affect the selected period's opening balance.
        val sorted = trades.asSequence()
            .filter { it.closeTime <= now }
            .sortedWith(compareBy<TradeJournalEntry> { it.closeTime }.thenBy { it.id })
            .toList()
        val start = cutoff(period, now)
        val previous = if (start == null) emptyList() else sorted.filter { it.closeTime < start }
        val included = sorted.filter { start == null || it.closeTime >= start }
        val opening = initialBalance + previous.sumOf { it.netProfitLoss }
        val closing = opening + included.sumOf { it.netProfitLoss }
        require(opening.isFinite() && closing.isFinite()) { "Invalid period balance" }
        return ResultsPeriodSnapshot(
            openingBalance = opening,
            closingBalance = closing,
            trades = included,
            metrics = StatisticsCalculator.calculate(opening, included, closing),
            curve = StatisticsCalculator.buildEquityCurve(opening, included)
        )
    }
}
