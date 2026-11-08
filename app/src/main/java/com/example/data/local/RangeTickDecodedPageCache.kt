package com.example.data.local

import com.example.core.market.RangePriceTick

/**
 * Small, account-scoped LRU of already verified and decoded BID quote pages.
 * Room remains the durable source; this avoids repeated GZIP decompression
 * when a user pans back and forth over the same historical hours.
 */
internal class RangeTickDecodedPageCache(
    private val maxQuotes: Int = 200_000,
    private val maxPages: Int = 128
) {
    init { require(maxQuotes > 0 && maxPages > 0) }

    data class Key(val source: String, val symbol: String, val from: Long, val to: Long)

    private val pages = LinkedHashMap<Key, List<RangePriceTick>>(16, 0.75f, true)
    private var retainedQuotes = 0

    @Synchronized
    fun get(key: Key): List<RangePriceTick>? = pages[key]

    @Synchronized
    fun put(key: Key, quotes: List<RangePriceTick>) {
        remove(key)
        // Empty pages cost little to decompress but can number in the
        // thousands (weekends). Never pin them in the in-memory cache.
        if (quotes.isEmpty() || quotes.size > maxQuotes) return
        pages[key] = quotes
        retainedQuotes += quotes.size
        while (retainedQuotes > maxQuotes || pages.size > maxPages) {
            val iterator = pages.entries.iterator()
            val oldest = iterator.next()
            retainedQuotes -= oldest.value.size
            iterator.remove()
        }
    }

    @Synchronized
    fun remove(key: Key) {
        pages.remove(key)?.let { retainedQuotes -= it.size }
    }

    @Synchronized
    fun statistics(): Pair<Int, Int> = pages.size to retainedQuotes
}
