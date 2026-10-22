package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe

/**
 * Strict parser for externally acquired real historical OHLCV files.
 * A CSV file is user-supplied market data, NOT verified exchange data.
 * Expected columns: timestamp_ms,open,high,low,close,volume
 * Timestamp is UTC epoch milliseconds; data must be chronologically ordered.
 */
object HistoricalCsvImporter {
    fun parse(
        csv: String,
        symbol: String,
        timeframe: Timeframe,
        provenance: String,
        maxBars: Int = 20_000
    ): List<Candle> {
        require(symbol.matches(Regex("[A-Z0-9._/-]{3,24}"))) { "Invalid instrument" }
        require(provenance.isNotBlank() && provenance.length <= 100) { "Source attribution required" }
        require(maxBars in 1..100_000)
        val lines = csv.lineSequence().filter { it.isNotBlank() }.iterator()
        require(lines.hasNext()) { "CSV is empty" }
        val header = lines.next().trim().removePrefix("\uFEFF").lowercase()
        require(header == "timestamp_ms,open,high,low,close,volume") { "Unsupported CSV columns" }
        val interval = timeframe.minutes * 60_000L
        val result = ArrayList<Candle>()
        var previous = Long.MIN_VALUE
        while (lines.hasNext()) {
            require(result.size < maxBars) { "CSV exceeds candle limit" }
            val fields = lines.next().trim().split(',')
            require(fields.size == 6) { "Invalid CSV row" }
            val time = fields[0].trim().toLongOrNull() ?: error("Invalid timestamp")
            val open = fields[1].trim().toDoubleOrNull() ?: error("Invalid open")
            val high = fields[2].trim().toDoubleOrNull() ?: error("Invalid high")
            val low = fields[3].trim().toDoubleOrNull() ?: error("Invalid low")
            val close = fields[4].trim().toDoubleOrNull() ?: error("Invalid close")
            val volume = fields[5].trim().toDoubleOrNull() ?: error("Invalid volume")
            require(time > previous && time >= 0L) { "Out-of-order or duplicate timestamp" }
            require(time % interval == 0L || timeframe.minutes == 10_080) { "Misaligned timestamp" }
            require(listOf(open, high, low, close, volume).all { it.isFinite() }) { "Non-finite OHLCV" }
            require(open > 0 && high >= maxOf(open, close) &&
                low > 0 && low <= minOf(open, close) && volume >= 0) { "Invalid OHLCV" }
            val end = Math.addExact(time, interval)
            result.add(Candle(
                symbol = symbol,
                timeframe = timeframe,
                openTime = time,
                closeTime = end,
                open = open,
                high = high,
                low = low,
                close = close,
                volume = volume,
                source = "USER_IMPORTED:$provenance"
            ))
            previous = time
        }
        require(result.isNotEmpty()) { "No historical candles" }
        return result
    }
}
