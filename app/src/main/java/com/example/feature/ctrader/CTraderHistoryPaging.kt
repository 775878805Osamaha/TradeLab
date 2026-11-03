package com.example.feature.ctrader

import com.example.core.model.Timeframe

/**
 * Date/count-safe historical paging for cTrader.
 *
 * The broker's count is a limit on the number of bars returned from toTimestamp.
 * A date window containing MORE theoretical bars than the requested count silently
 * skips older candles when advanced by window boundaries. That was the root of
 * detached/large-gap candle groups in long Replay lookback.
 *
 * Every window below contains at most count source-timeframe slots; the next
 * request starts at the exact preceding slot, even across a closed FX weekend.
 * No total lookback depth is imposed by this object.
 */
object CTraderHistoryPaging {
    private const val DAY_MS=86_400_000L
    data class Window(val from:Long,val to:Long,val sourcePeriod:String,
                      val sourceInterval:Long,val count:Int) {
        init {
            require(from>=0 && to>=from && sourceInterval>0 && count in 1..1000)
            require((to-from)/sourceInterval+1 <= count.toLong()) {
                "Historical request would skip source bars at count limit"
            }
        }
        fun earlierExclusive():Long = from
    }

    fun sourceTimeframe(frame:Timeframe):Timeframe =
        if(frame==Timeframe.H2) Timeframe.H1 else frame

    /** Per-period maximum calendar span, bounded by service's 90-day cap. */
    private fun maximumSpan(frame:Timeframe):Long = when(frame) {
        Timeframe.M1,Timeframe.M3,Timeframe.M5 -> 6L*DAY_MS
        Timeframe.M15 -> 7L*DAY_MS
        Timeframe.M30 -> 15L*DAY_MS
        Timeframe.H1,Timeframe.H2 -> 30L*DAY_MS
        Timeframe.H4 -> 60L*DAY_MS
        Timeframe.D1,Timeframe.W1 -> 89L*DAY_MS
    }

    /** Conservative span without skipping any of 500 returned source bars. */
    fun windowSpan(timeframe:Timeframe):Long {
        val source=sourceTimeframe(timeframe)
        val interval=source.minutes*60_000L
        val capacity=if(timeframe==Timeframe.H2)1000L else 500L
        return minOf(maximumSpan(timeframe),(capacity-1L)*interval+interval)
    }

    fun before(timeframe:Timeframe,oldestExclusive:Long,
               requestedCount:Int=if(timeframe==Timeframe.H2)1000 else 500):Window? {
        require(oldestExclusive>=0)
        require(requestedCount in 1..1000)
        val source=sourceTimeframe(timeframe)
        val interval=source.minutes*60_000L
        if(oldestExclusive<interval)return null
        val end=oldestExclusive-interval
        val allowedSlots=minOf(requestedCount.toLong(),
            ((maximumSpan(timeframe)-1L)/interval+1L).coerceAtLeast(1L))
        val start=(end-(allowedSlots-1L)*interval).coerceAtLeast(0L)
        return Window(start,end,source.code,interval,requestedCount)
    }
}
