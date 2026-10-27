package com.example.core.model

enum class Timeframe(val code: String, val minutes: Int, val displayName: String) {
    M1("M1", 1, "1m"),
    M3("M3", 3, "3m"),
    M5("M5", 5, "5m"),
    M15("M15", 15, "15m"),
    M30("M30", 30, "30m"),
    H1("H1", 60, "1h"),
    H2("H2", 120, "2h"),
    H4("H4", 240, "4h"),
    D1("D1", 1440, "1D"),
    W1("W1", 10080, "1W");

    companion object {
        fun fromCode(code: String): Timeframe = values().firstOrNull { it.code.equals(code, ignoreCase = true) } ?: M15
    }
}

enum class DataSourceType(val label: String, val isSimulated: Boolean) {
    LIVE_DATA("LIVE DATA", false),
    DEMO_DATA("DEMO DATA", false),
    REPLAY_DATA("REPLAY DATA", true),
    STALE_DATA("STALE DATA", false)
}

enum class ProviderConnectionStatus(val displayName: String) {
    DISCONNECTED("غير متصل"),
    CONNECTING("جاري الاتصال..."),
    CONNECTED("متصل"),
    RECONNECTING("إعادة الاتصال..."),
    DEGRADED("اتصال ضعيف"),
    ERROR("خطأ في الاتصال")
}

enum class QuoteStatus {
    FRESH,
    STALE,
    SUSPECT
}

data class MarketQuote(
    val symbol: String,
    val bid: Double,
    val ask: Double,
    val last: Double = (bid + ask) / 2.0,
    val spread: Double = ask - bid,
    val timestamp: Long = System.currentTimeMillis(),
    val source: String = "MARKET_FEED",
    val status: QuoteStatus = QuoteStatus.FRESH
)

data class MarketSymbol(
    val symbol: String,
    val displayName: String,
    val assetClass: String, // CRYPTO, METALS, FOREX, INDICES
    val baseAsset: String,
    val quoteAsset: String,
    val pricePrecision: Int,
    val quantityPrecision: Int,
    val tickSize: Double,
    val lotSize: Double = 1.0,
    val minimumQuantity: Double = 0.01,
    val maximumQuantity: Double = 100.0,
    val tradingSession: String = "24/7",
    val defaultSpreadPips: Double = 1.5,
    val dataSourceType: DataSourceType = DataSourceType.DEMO_DATA
)

data class SymbolInfo(
    val symbol: String,
    val name: String,
    val category: String, // Forex, Crypto, Metals, Indices
    val digits: Int,
    val pipSize: Double,
    val contractSize: Double,
    val minLot: Double = 0.01,
    val maxLot: Double = 100.0,
    val lotStep: Double = 0.01,
    val defaultSpreadPips: Double = 1.5,
    val isFavorite: Boolean = false
) {
    fun formatPrice(price: Double): String = String.format("%.${digits}f", price)
}

data class Tick(
    val symbol: String,
    val bid: Double,
    val ask: Double,
    val last: Double = (bid + ask) / 2.0,
    val timestamp: Long = System.currentTimeMillis(),
    val source: String = "MARKET_FEED",
    val volume: Double = 0.0
) : java.io.Serializable {
    val spread: Double get() = (ask - bid)
    val mid: Double get() = (ask + bid) / 2.0
}

data class Candle(
    val symbol: String,
    val timeframe: Timeframe,
    val openTime: Long,
    val closeTime: Long = openTime + (timeframe.minutes * 60000L),
    val open: Double,
    val high: Double,
    val low: Double,
    val close: Double,
    val volume: Double = 0.0,
    val source: String = "MARKET_FEED"
) : java.io.Serializable {
    val isBullish: Boolean get() = close >= open
    val isBearish: Boolean get() = close < open
    val body: Double get() = kotlin.math.abs(close - open)
    val range: Double get() = high - low

    /**
     * Validates data integrity rules:
     * high >= max(open, close)
     * low <= min(open, close)
     * high >= low
     * openTime < closeTime
     */
    fun isValid(): Boolean {
        if (openTime >= closeTime) return false
        if (high < maxOf(open, close)) return false
        if (low > minOf(open, close)) return false
        if (high < low) return false
        if (volume < 0.0) return false
        return true
    }
}

/**
 * High-performance viewport model for CandlestickChart.
 * Prevents rendering hidden candles outside the visible bounding box.
 */
data class ChartViewport(
    val startIndex: Int,
    val endIndex: Int,
    val zoom: Float,
    val horizontalOffset: Float,
    val priceMin: Double,
    val priceMax: Double
) {
    val visibleCount: Int get() = if (endIndex >= startIndex) endIndex - startIndex + 1 else 0
}
