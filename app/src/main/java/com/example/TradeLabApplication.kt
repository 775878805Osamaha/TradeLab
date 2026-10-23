package com.example

import android.app.Application
import com.example.core.history.HistoryKeyStore
import com.example.core.market.DefaultMarketDataProvider
import com.example.data.local.AppDatabase
import com.example.data.repository.MarketDataRepository
import com.example.data.repository.TradingRepository

class TradeLabApplication : Application() {

    val historyKeyStore: HistoryKeyStore by lazy { HistoryKeyStore(this) }


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
            symbolDao = database.symbolDao()
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
