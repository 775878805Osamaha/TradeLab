package com.example.core.market

/**
 * Plans an exact inclusive historical BID interval from independently verified
 * disk slices. A saved empty market interval still counts as verified coverage.
 * Different slice boundaries (e.g. after a density split) can be reused without
 * requesting their overlapping quotes again or inventing prices between them.
 */
object RangeTickCacheCoverage {
    data class Span(val from: Long, val to: Long) {
        init { require(from > 0L && to >= from) }
    }

    sealed interface Piece {
        val from: Long
        val to: Long

        data class Saved(val span: Span, override val from: Long, override val to: Long) : Piece
        data class Missing(override val from: Long, override val to: Long) : Piece
    }

    fun plan(from: Long, to: Long, saved: List<Span>): List<Piece> {
        require(from > 0L && to >= from)
        val overlapping = saved.filter { it.to >= from && it.from <= to }
            .sortedWith(compareBy<Span> { it.from }.thenByDescending { it.to })
        val result = ArrayList<Piece>()
        var cursor = from
        var index = 0
        while (cursor <= to) {
            var best: Span? = null
            // All previously scanned intervals end no later than the last
            // chosen one, so only newly reached starts can extend coverage.
            while (index < overlapping.size && overlapping[index].from <= cursor) {
                val candidate = overlapping[index++]
                if (candidate.to >= cursor && (best == null || candidate.to > best.to))
                    best = candidate
            }
            if (best != null) {
                val end = minOf(to, best.to)
                result += Piece.Saved(best, cursor, end)
                if (end == to) break
                cursor = end + 1L
            } else {
                val nextStart = overlapping.getOrNull(index)?.from
                val end = if (nextStart == null) to else minOf(to, nextStart - 1L)
                result += Piece.Missing(cursor, end)
                if (end == to) break
                cursor = end + 1L
            }
        }
        return result
    }
}
