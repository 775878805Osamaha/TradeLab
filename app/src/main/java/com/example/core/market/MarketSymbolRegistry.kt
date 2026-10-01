package com.example.core.market

import com.example.core.model.DataSourceType
import com.example.core.model.MarketSymbol
import com.example.core.model.SymbolInfo

object MarketSymbolRegistry {

    val SYMBOLS: List<MarketSymbol> = listOf(
        MarketSymbol(
            symbol = "BTCUSDT",
            displayName = "Bitcoin / Tether",
            assetClass = "CRYPTO",
            baseAsset = "BTC",
            quoteAsset = "USDT",
            pricePrecision = 2,
            quantityPrecision = 4,
            tickSize = 0.01,
            lotSize = 1.0,
            minimumQuantity = 0.001,
            maximumQuantity = 50.0,
            tradingSession = "24/7",
            defaultSpreadPips = 1.0,
            dataSourceType = DataSourceType.LIVE_DATA
        ),
        MarketSymbol(
            symbol = "ETHUSDT",
            displayName = "Ethereum / Tether",
            assetClass = "CRYPTO",
            baseAsset = "ETH",
            quoteAsset = "USDT",
            pricePrecision = 2,
            quantityPrecision = 4,
            tickSize = 0.01,
            lotSize = 1.0,
            minimumQuantity = 0.01,
            maximumQuantity = 200.0,
            tradingSession = "24/7",
            defaultSpreadPips = 1.5,
            dataSourceType = DataSourceType.LIVE_DATA
        ),
        MarketSymbol(
            symbol = "XAUUSD",
            displayName = "Gold / US Dollar",
            assetClass = "METALS",
            baseAsset = "XAU",
            quoteAsset = "USD",
            pricePrecision = 2,
            quantityPrecision = 2,
            tickSize = 0.01,
            lotSize = 100.0,
            minimumQuantity = 0.01,
            maximumQuantity = 50.0,
            tradingSession = "23/5",
            defaultSpreadPips = 2.5,
            dataSourceType = DataSourceType.DEMO_DATA
        ),
        MarketSymbol(
            symbol = "EURUSD",
            displayName = "Euro / US Dollar",
            assetClass = "FOREX",
            baseAsset = "EUR",
            quoteAsset = "USD",
            pricePrecision = 5,
            quantityPrecision = 2,
            tickSize = 0.00001,
            lotSize = 100000.0,
            minimumQuantity = 0.01,
            maximumQuantity = 100.0,
            tradingSession = "24/5",
            defaultSpreadPips = 1.2,
            dataSourceType = DataSourceType.DEMO_DATA
        ),
        MarketSymbol(
            symbol = "GBPUSD",
            displayName = "British Pound / US Dollar",
            assetClass = "FOREX",
            baseAsset = "GBP",
            quoteAsset = "USD",
            pricePrecision = 5,
            quantityPrecision = 2,
            tickSize = 0.00001,
            lotSize = 100000.0,
            minimumQuantity = 0.01,
            maximumQuantity = 100.0,
            tradingSession = "24/5",
            defaultSpreadPips = 1.8,
            dataSourceType = DataSourceType.DEMO_DATA
        ),
        MarketSymbol(
            symbol = "USDJPY",
            displayName = "US Dollar / Japanese Yen",
            assetClass = "FOREX",
            baseAsset = "USD",
            quoteAsset = "JPY",
            pricePrecision = 3,
            quantityPrecision = 2,
            tickSize = 0.001,
            lotSize = 100000.0,
            minimumQuantity = 0.01,
            maximumQuantity = 100.0,
            tradingSession = "24/5",
            defaultSpreadPips = 1.5,
            dataSourceType = DataSourceType.DEMO_DATA
        )
    )

    fun getSymbol(symbol: String): MarketSymbol {
        val norm = normalizeSymbol(symbol)
        return SYMBOLS.firstOrNull { it.symbol == norm } ?: MarketSymbol(
            symbol = norm,
            displayName = norm,
            assetClass = "GENERAL",
            baseAsset = norm.take(3),
            quoteAsset = norm.drop(3),
            pricePrecision = 2,
            quantityPrecision = 2,
            tickSize = 0.01,
            lotSize = 1.0,
            minimumQuantity = 0.01,
            maximumQuantity = 100.0,
            tradingSession = "24/7",
            defaultSpreadPips = 2.0,
            dataSourceType = DataSourceType.DEMO_DATA
        )
    }

    fun toSymbolInfo(ms: MarketSymbol): SymbolInfo = SymbolInfo(
        symbol = ms.symbol,
        name = ms.displayName,
        category = when (ms.assetClass) {
            "CRYPTO" -> "Crypto"
            "METALS" -> "Metals"
            "FOREX" -> "Forex"
            else -> "Indices"
        },
        digits = ms.pricePrecision,
        pipSize = ms.tickSize * (if (ms.assetClass == "FOREX" && ms.pricePrecision == 5) 10.0 else 1.0),
        contractSize = ms.lotSize,
        minLot = ms.minimumQuantity,
        maxLot = ms.maximumQuantity,
        lotStep = 0.01,
        defaultSpreadPips = ms.defaultSpreadPips,
        isFavorite = false
    )

    fun normalizeSymbol(symbol: String): String {
        return when (symbol.uppercase()) {
            "BTCUSD" -> "BTCUSDT"
            "ETHUSD" -> "ETHUSDT"
            else -> symbol.uppercase()
        }
    }
}
