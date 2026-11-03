package com.example.feature.replay

import com.example.core.model.Candle

/**
 * O(1) concatenation of inspectable broker prehistory and the revealed Replay
 * prefix. Unlike copying two lists, this allocates no 100k-item list on every
 * replay tick, while retaining normal List indexing and subList semantics for
 * the existing candlestick renderer and price-range index.
 *
 * The caller must pass immutable snapshots, never mutable accumulating buffers.
 * No candle after the Replay cursor is included.
 */
class ReplayChartSeries(
    private val older: List<Candle>,
    private val revealed: List<Candle>
) : AbstractList<Candle>(), java.util.RandomAccess {
    override val size: Int get() = older.size + revealed.size
    // Snapshot identity: StateFlow/Compose should not compare all 100k bars
    // structurally each time a new historical page or Replay tick arrives.
    override fun equals(other:Any?):Boolean=this===other
    override fun hashCode():Int=System.identityHashCode(this)

    override fun get(index: Int): Candle {
        if (index !in 0 until size) throw IndexOutOfBoundsException("index=$index size=$size")
        return if (index < older.size) older[index] else revealed[index - older.size]
    }
}
