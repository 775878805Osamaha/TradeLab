package com.example.core.market

import com.example.core.model.SymbolInfo

object DefaultSymbols {
    val SYMBOLS = listOf(
        SymbolInfo(
            symbol = "XAUUSD",
            name = "Gold / US Dollar",
            category = "Metals",
            digits = 2,
            pipSize = 0.01,
            contractSize = 100.0,
            minLot = 0.01,
            maxLot = 50.0,
            lotStep = 0.01,
            defaultSpreadPips = 25.0, // 0.25$ spread
            isFavorite = true
        ),
        SymbolInfo(
            symbol = "EURUSD",
            name = "Euro / US Dollar",
            category = "Forex",
            digits = 5,
            pipSize = 0.0001,
            contractSize = 100000.0,
            minLot = 0.01,
            maxLot = 100.0,
            lotStep = 0.01,
            defaultSpreadPips = 1.2,
            isFavorite = true
        ),
        SymbolInfo(
            symbol = "GBPUSD",
            name = "British Pound / US Dollar",
            category = "Forex",
            digits = 5,
            pipSize = 0.0001,
            contractSize = 100000.0,
            minLot = 0.01,
            maxLot = 100.0,
            lotStep = 0.01,
            defaultSpreadPips = 1.5,
            isFavorite = true
        ),
        SymbolInfo(
            symbol = "USDJPY",
            name = "US Dollar / Japanese Yen",
            category = "Forex",
            digits = 3,
            pipSize = 0.01,
            contractSize = 100000.0,
            minLot = 0.01,
            maxLot = 100.0,
            lotStep = 0.01,
            defaultSpreadPips = 1.4,
            isFavorite = false
        ),
        SymbolInfo(
            symbol = "BTCUSDT",
            name = "Bitcoin / Tether USDT",
            category = "Crypto",
            digits = 2,
            pipSize = 1.0,
            contractSize = 1.0,
            minLot = 0.01,
            maxLot = 20.0,
            lotStep = 0.01,
            defaultSpreadPips = 15.0,
            isFavorite = true
        ),
        SymbolInfo(
            symbol = "ETHUSDT",
            name = "Ethereum / Tether USDT",
            category = "Crypto",
            digits = 2,
            pipSize = 0.1,
            contractSize = 1.0,
            minLot = 0.01,
            maxLot = 50.0,
            lotStep = 0.01,
            defaultSpreadPips = 2.0,
            isFavorite = false
        )
    )

    val TERMINAL_FOREX = listOf(
        SymbolInfo("AUDUSD", "Australian Dollar / US Dollar", "Forex", 5, .0001, 100000.0),
        SymbolInfo("USDCAD", "US Dollar / Canadian Dollar", "Forex", 5, .0001, 100000.0),
        SymbolInfo("NZDUSD", "New Zealand Dollar / US Dollar", "Forex", 5, .0001, 100000.0),
        SymbolInfo("USDCHF", "US Dollar / Swiss Franc", "Forex", 5, .0001, 100000.0)
    )

    fun getSymbol(symbol: String): SymbolInfo {
        val normalized = when (symbol.uppercase()) {
            "BTCUSD" -> "BTCUSDT"
            "ETHUSD" -> "ETHUSDT"
            else -> symbol.uppercase()
        }
        return (SYMBOLS + TERMINAL_FOREX).firstOrNull { it.symbol.equals(normalized, ignoreCase = true) }
            ?: SymbolInfo(
                symbol = symbol,
                name = symbol,
                category = "Custom",
                digits = 2,
                pipSize = 0.01,
                contractSize = 100.0
            )
    }
}
