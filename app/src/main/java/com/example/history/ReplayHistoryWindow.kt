package com.example.history

/**
 * An immutable, strictly bounded view of historical candles for replay.
 * Consumers can only access candles at or before the revealed index.
 * Does not interpolate missing prices.
 */
class ReplayHistoryWindow private constructor(
    private val bars: List<HistoryIntegrityAudit.Bar>,
    val revealedIndex: Int
) {
    val size: Int get() = revealedIndex + 1
    val isEmpty: Boolean get() = size == 0
    val latest: HistoryIntegrityAudit.Bar? get() = if (isEmpty) null else bars[revealedIndex]

    fun visibleBars(): List<HistoryIntegrityAudit.Bar> =
        if (isEmpty) emptyList() else bars.subList(0, size).toList()

    fun last(count: Int): List<HistoryIntegrityAudit.Bar> {
        require(count >= 0) { "count must not be negative" }
        if (count == 0 || isEmpty) return emptyList()
        return bars.subList((size - count).coerceAtLeast(0), size).toList()
    }

    fun advance(steps: Int = 1): ReplayHistoryWindow {
        require(steps >= 0) { "steps must not be negative" }
        return ReplayHistoryWindow(bars, (revealedIndex.toLong() + steps).coerceAtMost(bars.lastIndex.toLong()).toInt())
    }

    fun rewind(steps: Int = 1): ReplayHistoryWindow {
        require(steps >= 0) { "steps must not be negative" }
        return ReplayHistoryWindow(bars, (revealedIndex.toLong() - steps).coerceAtLeast(-1).toInt())
    }

    companion object {
        fun fromValidated(
            report: HistoryIntegrityAudit.Report,
            initialVisible: Int = 0,
            rejectFindings: Boolean = true
        ): ReplayHistoryWindow {
            require(initialVisible >= 0) { "initialVisible must not be negative" }
            require(!rejectFindings || report.clean) { "History integrity findings require explicit review" }
            return ReplayHistoryWindow(report.accepted.toList(), initialVisible.coerceAtMost(report.accepted.size) - 1)
        }
    }
}
