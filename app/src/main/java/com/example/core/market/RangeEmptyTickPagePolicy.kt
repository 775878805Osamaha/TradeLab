package com.example.core.market

/**
 * An empty successful response is not permanent proof that a broker has no
 * history there. Keep it briefly to avoid repeated weekend requests, then
 * check cTrader again so temporary empty API pages cannot create lasting gaps.
 * Non-empty, validated BID pages remain reusable without a time limit.
 */
object RangeEmptyTickPagePolicy {
    const val RECENT_MARKET_HORIZON_MILLIS = 36L * 3_600_000L
    const val RECENT_EMPTY_TTL_MILLIS = 15L * 60_000L
    const val HISTORICAL_EMPTY_TTL_MILLIS = 24L * 3_600_000L

    fun reusable(quoteCount: Int, pageEnd: Long, savedAt: Long, now: Long): Boolean {
        if (quoteCount < 0) return false
        if (quoteCount > 0) return true
        if (savedAt <= 0L || now < savedAt) return false
        val ttl = if (pageEnd >= now - RECENT_MARKET_HORIZON_MILLIS)
            RECENT_EMPTY_TTL_MILLIS else HISTORICAL_EMPTY_TTL_MILLIS
        return now - savedAt < ttl
    }
}
