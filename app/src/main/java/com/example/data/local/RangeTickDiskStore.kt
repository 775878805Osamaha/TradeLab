package com.example.data.local

import com.example.core.market.RangePriceTick
import com.example.core.market.RangeTickCacheCodec
import com.example.core.market.RangeTickCacheCoverage
import com.example.core.market.RangeEmptyTickPagePolicy
import com.example.core.market.RangeTickWindowReuse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap

/**
 * Persistent cTrader BID quote pages, keyed by the selected broker account's
 * sourceKey, symbol and exact covered milliseconds. Empty pages are briefly
 * cached to avoid needless weekend requests, then rechecked with the broker.
 *
 * SQLite stores compressed lossless pages rather than millions of individual
 * rows. A request with different boundaries reuses all covered saved portions
 * and asks cTrader ONLY for the uncovered gaps. Cache write failures never
 * replace real history with synthetic data or prevent a network response.
 */
class RangeTickDiskStore(
    private val dao: RangeTickSliceDao,
    private val nowMillis: () -> Long = { System.currentTimeMillis() },
    maxDecodedQuotes: Int = 200_000
) {
    private val decodedPages = RangeTickDecodedPageCache(maxDecodedQuotes)
    // Two overlapping deep pans must not both fetch the same missing BID
    // page. Different brokers/symbols can still load independently.
    private val downloadLocks = ConcurrentHashMap<Pair<String, String>, Mutex>()

    /** Invalidate materialized Range bars if their source window included a
     * temporary zero-quote response which is now due for re-verification. */
    suspend fun hasExpiredEmptyPages(source: String, symbol: String,
                                     from: Long, to: Long): Boolean {
        return try {
            val now = nowMillis()
            dao.covered(source, symbol, from, to).any { page ->
                !RangeEmptyTickPagePolicy.reusable(page.quoteCount, page.toMillis,
                    page.savedAtMillis, now)
            }
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { false }
    }

    private suspend fun safelyDiscard(source: String, symbol: String, from: Long, to: Long) {
        decodedPages.remove(RangeTickDecodedPageCache.Key(source, symbol, from, to))
        try { dao.discard(source, symbol, from, to) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { /* Disk failure must not hide genuine BID quotes. */ }
    }

    private suspend fun cachedPage(source: String, symbol: String,
                                   span: RangeTickCacheCoverage.Span): List<RangePriceTick>? {
        val key = RangeTickDecodedPageCache.Key(source, symbol, span.from, span.to)
        decodedPages.get(key)?.let { return it }
        return try {
            val row = dao.find(source, symbol, span.from, span.to) ?: return null
            val decoded = RangeTickCacheCodec.decode(row.compressedBidQuotes, row.quoteCount,
                row.fromMillis, row.toMillis)
            decodedPages.put(key, decoded)
            decoded
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) {
            safelyDiscard(source, symbol, span.from, span.to)
            null
        }
    }

    suspend fun getOrDownload(source: String, symbol: String, from: Long, to: Long,
                              download: suspend (Long, Long) -> List<RangePriceTick>): List<RangePriceTick> {
        require(source.startsWith("ctrader:") && symbol.isNotBlank() && from > 0 && to >= from)
        // Coverage is planned *after* acquiring the lock so the second
        // request observes pages durably written by the first one.
        val lock = downloadLocks.computeIfAbsent(source to symbol) { Mutex() }
        return lock.withLock { loadExclusive(source, symbol, from, to, download) }
    }

    private suspend fun loadExclusive(source: String, symbol: String, from: Long, to: Long,
                                      download: suspend (Long, Long) -> List<RangePriceTick>): List<RangePriceTick> {
        val saved = try { dao.covered(source, symbol, from, to) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { emptyList() }
        val now = nowMillis()
        val (reusable, expired) = saved.partition {
            RangeEmptyTickPagePolicy.reusable(it.quoteCount, it.toMillis, it.savedAtMillis, now)
        }
        // Discard only expired empty intervals. Valid non-empty BID quotes
        // never expire, and unrelated account data is left untouched.
        for (page in expired) safelyDiscard(source, symbol, page.fromMillis, page.toMillis)
        val plan = RangeTickCacheCoverage.plan(from, to,
            reusable.map { RangeTickCacheCoverage.Span(it.fromMillis, it.toMillis) })
        val combined = ArrayList<RangePriceTick>()
        for (piece in plan) {
            currentCoroutineContext().ensureActive()
            val cached = if (piece is RangeTickCacheCoverage.Piece.Saved)
                cachedPage(source, symbol, piece.span) else null
            if (cached != null) {
                combined.addAll(RangeTickWindowReuse.between(cached, piece.from, piece.to))
                continue
            }
            val verified = download(piece.from, piece.to)
            // Check BEFORE persisting, including the repeated-timestamp order
            // permitted by cTrader. An invalid page is never marked covered.
            RangeTickCacheCodec.validate(verified, piece.from, piece.to)
            combined.addAll(verified)
            try {
                dao.save(RangeTickSliceEntity(source, symbol, piece.from, piece.to,
                    verified.size, RangeTickCacheCodec.encode(verified, piece.from, piece.to),
                    nowMillis()))
                decodedPages.put(RangeTickDecodedPageCache.Key(source, symbol, piece.from, piece.to),
                    verified)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { /* Continue displaying verified broker data. */ }
        }
        RangeTickCacheCodec.validate(combined, from, to)
        return combined
    }
}
