package com.example.core.market

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/** Lossless, versioned storage of real cTrader BID quote timestamps/prices. */
object RangeTickCacheCodec {
    private const val MAGIC = 0x52544B31 // RTK1

    fun validate(ticks: List<RangePriceTick>, from: Long, to: Long) {
        require(from > 0 && to >= from && ticks.size <= RangeTickBatchLoader.MAX_WINDOW_TICKS)
        var previous = from
        for (tick in ticks) {
            require(tick.timestamp in from..to && tick.timestamp >= previous &&
                tick.price.isFinite() && tick.price > 0.0) { "Unverified BID quote cache page" }
            previous = tick.timestamp
        }
    }

    fun encode(ticks: List<RangePriceTick>, from: Long, to: Long): ByteArray {
        validate(ticks, from, to)
        val output = ByteArrayOutputStream()
        DataOutputStream(GZIPOutputStream(output)).use { writer ->
            writer.writeInt(MAGIC)
            writer.writeInt(ticks.size)
            for (tick in ticks) {
                writer.writeLong(tick.timestamp)
                writer.writeDouble(tick.price)
            }
        }
        return output.toByteArray()
    }

    fun decode(payload: ByteArray, expectedCount: Int, from: Long, to: Long): List<RangePriceTick> {
        require(expectedCount in 0..RangeTickBatchLoader.MAX_WINDOW_TICKS)
        return DataInputStream(GZIPInputStream(ByteArrayInputStream(payload))).use { reader ->
            require(reader.readInt() == MAGIC) { "Unsupported range cache version" }
            val count = reader.readInt()
            require(count == expectedCount) { "Range cache quote count mismatch" }
            val result = ArrayList<RangePriceTick>(count)
            repeat(count) { result += RangePriceTick(reader.readLong(), reader.readDouble()) }
            require(reader.read() == -1) { "Trailing bytes in range cache page" }
            validate(result, from, to)
            result
        }
    }
}
