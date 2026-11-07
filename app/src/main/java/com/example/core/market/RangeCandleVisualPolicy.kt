package com.example.core.market

/** Real Range bodies stay opaque even if the old chart-wide "hollow up"
 * preference is enabled. Only explicitly labelled, visual-only gap markers
 * may be translucent outlines; they can never masquerade as market candles. */
object RangeCandleVisualPolicy {
    fun outline(isRangeChart: Boolean, isVisualOnlyGap: Boolean,
                isBullish: Boolean, hollowUp: Boolean, hollowChart: Boolean): Boolean =
        isVisualOnlyGap || (!isRangeChart && isBullish && (hollowUp || hollowChart))
}
