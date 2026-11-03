package com.example.feature.ctrader

/**
 * Small in-memory LRU for immutable, completed broker OHLC pages.
 * Account ID and broker-specific symbol ID are part of every key: a gold
 * symbol on two cTrader brokers never shares candles or symbol resolution.
 *
 * No OAuth credentials, sessions or private account details are cached.
 * Pages are kept only in this process and cleared on re-authorisation.
 */
class CTraderHistoricalPageCache(private val maxPages:Int=48) {
    init { require(maxPages in 1..256) }
    data class Key(
        val accountId:String,
        val symbolId:Long,
        val timeframe:String,
        val from:Long,
        val to:Long,
        val count:Int
    ) {
        init {
            require(accountId.isNotBlank() && symbolId>0L)
            require(from>=0L && to>=from && count in 1..1000)
        }
    }

    private val pages=object : LinkedHashMap<Key,List<CTraderReadOnlyMarketApi.BrokerCandle>>(
        maxPages+1,0.75f,true
    ) {
        override fun removeEldestEntry(
            eldest:MutableMap.MutableEntry<Key,List<CTraderReadOnlyMarketApi.BrokerCandle>>?
        ):Boolean=size>maxPages
    }

    @Synchronized fun get(key:Key):List<CTraderReadOnlyMarketApi.BrokerCandle>?=pages[key]
    @Synchronized fun put(key:Key,bars:List<CTraderReadOnlyMarketApi.BrokerCandle>) {
        // Immutable List snapshot: a caller cannot mutate the original array
        // after it has been authenticated and validated for its time range.
        pages[key]=bars.toList()
    }
    @Synchronized fun clear(){pages.clear()}
    @Synchronized fun size():Int=pages.size
}
