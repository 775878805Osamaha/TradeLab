package com.example

import android.app.Application
import com.example.core.market.DefaultMarketDataProvider
import com.example.core.market.CTraderGatewayClient
import com.example.data.local.AppDatabase
import com.example.data.repository.MarketDataRepository
import com.example.data.repository.TradingRepository

class TradeLabApplication : Application() {

    val cTrader: CTraderGatewayClient by lazy { CTraderGatewayClient(this) }

    val trainingSessionStore by lazy { com.example.feature.replay.TrainingSessionStore(this, database) }

    val database: AppDatabase by lazy {
        AppDatabase.getInstance(this)
    }

    val marketDataProvider: DefaultMarketDataProvider by lazy {
        DefaultMarketDataProvider(cTrader = cTrader)
    }

    val marketDataRepository: MarketDataRepository by lazy {
        MarketDataRepository(
            provider = marketDataProvider,
            candleDao = database.candleDao(),
            symbolDao = database.symbolDao(),
            cTrader = cTrader
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
