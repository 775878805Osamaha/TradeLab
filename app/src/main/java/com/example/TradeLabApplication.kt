package com.example

import android.app.Application
import com.example.core.market.DefaultMarketDataProvider
import com.example.data.local.AppDatabase
import com.example.data.repository.MarketDataRepository
import com.example.data.repository.TradingRepository

class TradeLabApplication : Application() {

    val trainingSessionStore by lazy { com.example.feature.replay.TrainingSessionStore(this, database) }



    val database: AppDatabase by lazy {
        AppDatabase.getInstance(this)
    }

    val marketDataProvider: DefaultMarketDataProvider by lazy {
        DefaultMarketDataProvider()
    }

    val cTraderChartSource by lazy { com.example.feature.ctrader.CTraderChartSource(this) }

    val marketDataRepository: MarketDataRepository by lazy {
        MarketDataRepository(
            provider = marketDataProvider,
            candleDao = database.candleDao(),
            symbolDao = database.symbolDao(),
            archiveDirectory = java.io.File(cacheDir, "chart-archives-v1"),
            ctrader = cTraderChartSource
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
