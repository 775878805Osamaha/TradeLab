package com.example.core.market

import com.example.core.model.Candle

/** Date search retries only confirmed empty sessions; transport/integrity errors propagate. */
object ReplayDateHistory {
    data class Loaded(val window: ReplayDateWindow.Window, val candles: List<Candle>)

    suspend fun load(
        windows: List<ReplayDateWindow.Window>,
        target: Long?,
        fetch: suspend (Long, Long) -> List<Candle>
    ): Loaded? {
        for (window in windows) {
            val candidate = try {
                fetch(window.from, window.to)
            } catch (empty: NoHistoricalCandlesException) {
                if (target == null) throw empty
                emptyList()
            }
            require(candidate.all { it.openTime in window.from..window.to }) {
                "Historical provider returned candles outside requested date window"
            }
            if (candidate.size >= 2 && (target == null || candidate.any { it.openTime >= target })) {
                return Loaded(window, candidate)
            }
            if (target == null) break
        }
        return null
    }
}
