package com.example.feature.chart.model

/**
 * Distinguishes an intentional pull past the oldest loaded candle from a
 * stationary viewport. A history load is requested at most once per touch;
 * another deliberate touch can retry after a provider/network failure.
 *
 * This is particularly important when fewer candles exist than fit on screen:
 * the viewport rightly clamps to zero, yet pulling right must still be able
 * to request older real data.
 */
class ChartHistoryEdgePull {
    private var accumulatedOverscroll = 0f
    private var fired = false

    fun beginTouch() {
        accumulatedOverscroll = 0f
        fired = false
    }

    fun rightPull(
        requestedOffsetPx: Float,
        clampedOffsetPx: Float,
        minimumPullPx: Float,
        canRequest: Boolean
    ): Boolean {
        if (fired) return false
        val overflow = requestedOffsetPx - clampedOffsetPx
        if (!overflow.isFinite() || overflow <= 0f) {
            accumulatedOverscroll = 0f
            return false
        }
        accumulatedOverscroll += overflow
        if (!canRequest || accumulatedOverscroll < minimumPullPx.coerceAtLeast(1f)) return false
        fired = true
        return true
    }
}
