package com.example.feature.replay

import com.example.core.model.Candle
import com.example.core.model.Timeframe

/**
 * Immutable chunked chronological history for Replay inspection.
 *
 * A 100,000-bar history consists of about 200 small broker pages, not a new
 * 100,000-item ArrayList every time the user drags another 500 candles back.
 * Prepend allocates O(page count) metadata, never copies existing OHLC objects
 * or their references. Indexed access is O(log pages).
 *
 * This type is constructed ONLY from pages validated by ReplayChartLookback.
 */
internal class ReplayHistoricalPages private constructor(
    private val pages:List<List<Candle>>,
    val sourceSymbol:String,
    val sourceTimeframe:Timeframe,
    val replayFirstOpen:Long
):AbstractList<Candle>(),java.util.RandomAccess {
    private val pageEnds:IntArray
    override val size:Int

    init {
        var total=0L
        pageEnds=IntArray(pages.size) { index ->
            total += pages[index].size.toLong()
            require(total<=Int.MAX_VALUE.toLong()) { "Historical chart exceeds platform limits" }
            total.toInt()
        }
        size=total.toInt()
    }

    override fun get(index:Int):Candle {
        if(index<0 || index>=size)throw IndexOutOfBoundsException("index=$index size=$size")
        var left=0
        var right=pageEnds.lastIndex
        while(left<right) {
            val mid=(left+right) ushr 1
            if(index<pageEnds[mid])right=mid else left=mid+1
        }
        val start=if(left==0)0 else pageEnds[left-1]
        return pages[left][index-start]
    }

    fun prependVerified(page:List<Candle>):ReplayHistoricalPages {
        if(page.isEmpty())return this
        require(isEmpty() || page.last().openTime<first().openTime) {
            "This is not a strict older history page"
        }
        return ReplayHistoricalPages(listOf(page)+pages,
            sourceSymbol,sourceTimeframe,replayFirstOpen)
    }

    fun belongsTo(symbol:String,timeframe:Timeframe,boundary:Long):Boolean =
        sourceSymbol.equals(symbol,ignoreCase=true) &&
            sourceTimeframe==timeframe && replayFirstOpen==boundary

    companion object {
        fun verified(page:List<Candle>,symbol:String,timeframe:Timeframe,
                     replayFirstOpen:Long):ReplayHistoricalPages {
            require(page.isNotEmpty())
            return ReplayHistoricalPages(listOf(page),symbol,timeframe,replayFirstOpen)
        }
    }
}
