package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.DataSourceType
import com.example.core.model.ProviderConnectionStatus
import com.example.core.model.Tick
import com.example.core.model.Timeframe
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

interface MarketDataProvider {
    val isConnected: StateFlow<Boolean>
    val connectionStatus: StateFlow<ProviderConnectionStatus>
    val dataSourceType: StateFlow<DataSourceType>
    val providerName: String

    suspend fun connect()
    suspend fun disconnect()
    suspend fun subscribe(symbol: String)
    suspend fun unsubscribe(symbol: String)
    suspend fun getLatestTick(symbol: String): Tick?
    suspend fun getHistoricalCandles(symbol: String, timeframe: Timeframe, from: Long, to: Long): List<Candle>
    fun observeTicks(symbol: String): Flow<Tick>
    fun observeCandles(symbol: String, timeframe: Timeframe): Flow<Candle>
}

interface HistoricalDataProvider {
    suspend fun loadHistoricalRange(
        symbol: String,
        timeframe: Timeframe,
        fromTimestamp: Long,
        toTimestamp: Long
    ): List<Candle>
}

interface StreamingMarketDataProvider : MarketDataProvider {
    val streamReconnectAttempts: StateFlow<Int>
    suspend fun startStreaming(symbols: List<String>)
    suspend fun stopStreaming()
    fun observeRawStream(): Flow<String>
}

interface WebSocketMarketDataProvider : StreamingMarketDataProvider {
    suspend fun connectWebSocket(endpointUrl: String)
}
