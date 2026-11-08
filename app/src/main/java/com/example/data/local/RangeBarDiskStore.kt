package com.example.data.local

import com.example.core.market.RangeBarSnapshotCodec
import com.example.core.market.RangeBarWarmRestorePolicy
import com.example.core.market.VerifiedRangeBars
import kotlinx.coroutines.CancellationException

/** Source/account-scoped materialized Range candles, built only from fully verified BID windows. */
class RangeBarDiskStore(private val dao: RangeBarSnapshotDao) {
    data class Saved(val from: Long, val to: Long, val result: VerifiedRangeBars)

    private suspend fun decode(row: RangeBarSnapshotEntity): Saved? {
        return try {
            val bars = RangeBarSnapshotCodec.decode(row.symbol, row.source, row.compressedCandles)
            require(bars.candles.all { it.openTime >= row.fromMillis &&
                it.openTime <= row.toMillis && it.closeTime <= row.toMillis + 1L }) {
                "Saved Range bars exceeded their verified BID window"
            }
            Saved(row.fromMillis, row.toMillis, bars)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) {
            try { dao.discard(row.source, row.symbol, row.fromMillis, row.toMillis,
                row.rangeTicks, row.tickSizeBits, row.includeIncomplete) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { }
            null
        }
    }

    suspend fun exact(symbol: String, source: String, from: Long, to: Long,
                      size: Int, tickSize: Double, includeIncomplete: Boolean): VerifiedRangeBars? {
        return try {
            val row = dao.exact(source, symbol, from, to, size, tickSize.toBits(),
                includeIncomplete) ?: return null
            decode(row)?.result
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { null }
    }

    suspend fun newestCompatible(symbol: String, source: String, from: Long, to: Long,
                                 size: Int, tickSize: Double, includeIncomplete: Boolean): Saved? {
        return try {
            val rows = dao.overlappingPreviews(source, symbol, size, tickSize.toBits(),
                includeIncomplete, (to - RangeBarWarmRestorePolicy.MAX_PREVIEW_STALE_MILLIS)
                    .coerceAtLeast(1L), to, from)
            for (row in rows) {
                if (!RangeBarWarmRestorePolicy.canPreview(row.fromMillis, row.toMillis, from, to))
                    continue
                val safe = decode(row)
                if (safe != null) return safe
            }
            null
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { null }
    }

    suspend fun save(symbol: String, source: String, from: Long, to: Long,
                     size: Int, tickSize: Double, includeIncomplete: Boolean,
                     bars: VerifiedRangeBars) {
        require(from > 0L && to >= from && size in 1..100_000)
        require(bars.candles.all { it.openTime >= from && it.openTime <= to &&
            it.closeTime <= to + 1L }) { "Cannot persist unverified future Range candles" }
        // A transient empty broker page is not evidence that there is no
        // historic market data. Retry that window on the next chart open.
        if (bars.diagnostics.quoteCount == 0) return
        try {
            // Keep the *last* fully verified cutoff in each five-minute time
            // bucket. Skipping near-duplicates instead left only an older
            // snapshot on disk: reopening the exact last-seen chart then
            // had to rescan hundreds of thousands of quotes. Replacing the
            // nearby materialization preserves fast exact restoration while
            // bounding Replay snapshot growth. Broker BID pages are NEVER
            // deleted by this operation.
            val interval = RangeBarWarmRestorePolicy.SNAPSHOT_COALESCE_MILLIS
            val bucketStart = to / interval * interval
            val bucketEnd = bucketStart + interval - 1L
            dao.saveCoalesced(RangeBarSnapshotEntity(source, symbol, from, to,
                size, tickSize.toBits(), includeIncomplete,
                RangeBarSnapshotCodec.encode(symbol, source, bars), System.currentTimeMillis()),
                bucketStart, bucketEnd, (from - interval).coerceAtLeast(1L), from + interval)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { /* Failure to save does not discard verified in-memory bars. */ }
    }
}
