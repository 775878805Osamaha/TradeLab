package com.example

import android.app.Application
import com.example.core.market.DefaultMarketDataProvider
import com.example.data.local.AppDatabase
import com.example.data.repository.MarketDataRepository
import com.example.data.repository.TradingRepository

class TradeLabApplication : Application() {

    val historyKeyStore by lazy { com.example.core.history.HistoryKeyStore(this) }
    val twelveDataHistory by lazy {
        com.example.core.history.TwelveDataHistory(
            apiKey = { historyKeyStore.read() },
            directory = java.io.File(noBackupFilesDir, "twelve-data-history"),
            errorText = { reason ->
                getString(when (reason) {
                    com.example.core.history.HistoryError.KEY -> R.string.history_key_required
                    com.example.core.history.HistoryError.SYMBOL -> R.string.history_symbol_error
                    com.example.core.history.HistoryError.INTERVAL -> R.string.history_interval_error
                    com.example.core.history.HistoryError.RANGE -> R.string.history_range_error
                    com.example.core.history.HistoryError.ACCESS -> R.string.history_access_error
                    com.example.core.history.HistoryError.LIMIT -> R.string.history_limit_error
                    com.example.core.history.HistoryError.NETWORK -> R.string.history_network_error
                    com.example.core.history.HistoryError.INVALID -> R.string.history_invalid_error
                    com.example.core.history.HistoryError.EMPTY -> R.string.history_empty_error
                })
            }
        )
    }

    val database: AppDatabase by lazy {
        AppDatabase.getInstance(this)
    }

    val marketDataProvider: DefaultMarketDataProvider by lazy {
        DefaultMarketDataProvider()
    }

    val marketDataRepository: MarketDataRepository by lazy {
        MarketDataRepository(
            provider = marketDataProvider,
            candleDao = database.candleDao(),
            symbolDao = database.symbolDao(),
            forexHistory = twelveDataHistory
        )
    }

    val tradingRepository: TradingRepository by lazy {
        TradingRepository(
            accountDao = database.accountDao(),
            positionDao = database.positionDao(),
            orderDao = database.orderDao(),
            tradeDao = database.tradeDao(),
            backtestDao = database.backtestDao()
        )
    }
}
