package com.example.data.local

import com.example.core.market.RangePriceTick
import com.example.core.market.RangeTickCacheCodec
import com.example.core.market.RangeTickCacheCoverage
import com.example.core.market.RangeTickWindowReuse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * Persistent cTrader BID quote pages, keyed by the selected broker account's
 * sourceKey, symbol and exact covered milliseconds. Every empty page is also
 * saved so an inactive market session is not repeatedly downloaded.
 *
 * SQLite stores compressed lossless pages rather than millions of individual
 * rows. A request with different boundaries reuses all covered saved portions
 * and asks cTrader ONLY for the uncovered gaps. Cache write failures never
 * replace real history with synthetic data or prevent a network response.
 */
class RangeTickDiskStore(private val dao: RangeTickSliceDao) {
    private suspend fun safelyDiscard(source: String, symbol: String, from: Long, to: Long) {
        try { dao.discard(source, symbol, from, to) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { /* Disk failure must not hide genuine BID quotes. */ }
    }

    private suspend fun cachedPage(source: String, symbol: String,
                                   span: RangeTickCacheCoverage.Span): List<RangePriceTick>? {
        return try {
            val row = dao.find(source, symbol, span.from, span.to) ?: return null
            RangeTickCacheCodec.decode(row.compressedBidQuotes, row.quoteCount,
                row.fromMillis, row.toMillis)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) {
            safelyDiscard(source, symbol, span.from, span.to)
            null
        }
    }

    suspend fun getOrDownload(source: String, symbol: String, from: Long, to: Long,
                              download: suspend (Long, Long) -> List<RangePriceTick>): List<RangePriceTick> {
        require(source.startsWith("ctrader:") && symbol.isNotBlank() && from > 0 && to >= from)
        val saved = try { dao.covered(source, symbol, from, to) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { emptyList() }
        val plan = RangeTickCacheCoverage.plan(from, to,
            saved.map { RangeTickCacheCoverage.Span(it.fromMillis, it.toMillis) })
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
                    System.currentTimeMillis()))
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { /* Continue displaying verified broker data. */ }
        }
        RangeTickCacheCodec.validate(combined, from, to)
        return combined
    }
}
