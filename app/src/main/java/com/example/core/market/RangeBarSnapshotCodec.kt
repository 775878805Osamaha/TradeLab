package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/**
 * Versioned, lossless materialization of a FINISHED genuine-BID Range scan.
 * A stored bar is never an OHLC substitute for the broker's original ticks:
 * missing history is still filled from the verified tick cache / cTrader.
 */
object RangeBarSnapshotCodec {
    private const val MAGIC = 0x52425331 // RBS1
    private const val MAX_BARS = 500_000

    fun encode(symbol: String, source: String, result: VerifiedRangeBars): ByteArray {
        require(symbol.isNotBlank() && source.startsWith("ctrader:"))
        require(result.candles.size <= MAX_BARS)
        val output = ByteArrayOutputStream()
        DataOutputStream(GZIPOutputStream(output)).use { writer ->
            writer.writeInt(MAGIC)
            writer.writeInt(result.candles.size)
            for (bar in result.candles) {
                validateBar(bar, symbol, source)
                writer.writeLong(bar.openTime)
                writer.writeLong(bar.closeTime)
                writer.writeDouble(bar.open)
                writer.writeDouble(bar.high)
                writer.writeDouble(bar.low)
                writer.writeDouble(bar.close)
                writer.writeDouble(bar.volume)
            }
            result.diagnostics.let { d ->
                writer.writeInt(d.quoteCount)
                writer.writeInt(d.sameMillisecondQuotes)
                writer.writeInt(d.jumpsOverOneRange)
                writer.writeLong(d.largestQuoteJumpTicks)
                writer.writeLong(d.longestQuotePauseMillis)
                writer.writeInt(d.oversizedCandles)
            }
            writer.writeBoolean(result.hasIncompleteLastBar)
        }
        return output.toByteArray()
    }

    fun decode(symbol: String, source: String, payload: ByteArray): VerifiedRangeBars {
        require(symbol.isNotBlank() && source.startsWith("ctrader:"))
        return DataInputStream(GZIPInputStream(ByteArrayInputStream(payload))).use { reader ->
            require(reader.readInt() == MAGIC) { "Unknown saved Range bar format" }
            val count = reader.readInt()
            require(count in 0..MAX_BARS) { "Invalid saved Range bar count" }
            val bars = ArrayList<Candle>(count)
            repeat(count) {
                val bar = Candle(symbol, Timeframe.M1, reader.readLong(), reader.readLong(),
                    reader.readDouble(), reader.readDouble(), reader.readDouble(),
                    reader.readDouble(), reader.readDouble(), source)
                validateBar(bar, symbol, source)
                bars += bar
            }
            val diagnostics = RangeTickDiagnostics(reader.readInt(), reader.readInt(),
                reader.readInt(), reader.readLong(), reader.readLong(), reader.readInt())
            require(diagnostics.quoteCount >= 0 && diagnostics.sameMillisecondQuotes >= 0 &&
                diagnostics.jumpsOverOneRange >= 0 && diagnostics.largestQuoteJumpTicks >= 0 &&
                diagnostics.longestQuotePauseMillis >= 0 && diagnostics.oversizedCandles >= 0)
            val incomplete = reader.readBoolean()
            require(reader.read() == -1) { "Trailing bytes in saved Range bars" }
            VerifiedRangeBars(bars, diagnostics, incomplete)
        }
    }

    private fun validateBar(bar: Candle, symbol: String, source: String) {
        require(bar.symbol == symbol && bar.source == source && bar.timeframe == Timeframe.M1 &&
            bar.open.isFinite() && bar.high.isFinite() && bar.low.isFinite() &&
            bar.close.isFinite() && bar.volume.isFinite() && bar.low > 0.0 && bar.isValid()) {
            "Invalid cached genuine Range candle"
        }
    }
}

/** Old completed windows may be displayed ONLY while a matching newer cutoff loads. */
object RangeBarWarmRestorePolicy {
    const val MAX_STALE_MILLIS = 5L * 60_000L

    fun canPreview(savedFrom: Long, savedTo: Long, requestedFrom: Long, requestedTo: Long): Boolean =
        requestedFrom > 0L && requestedTo >= requestedFrom && savedFrom > 0L &&
        savedTo >= savedFrom && savedTo <= requestedTo &&
        requestedTo - savedTo <= MAX_STALE_MILLIS &&
        kotlin.math.abs(requestedFrom - savedFrom) <= MAX_STALE_MILLIS
}
