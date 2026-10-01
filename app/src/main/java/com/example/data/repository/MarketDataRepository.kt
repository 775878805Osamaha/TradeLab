package com.example.data.repository

import com.example.core.market.DataIntegrityValidator
import com.example.core.market.DefaultMarketDataProvider
import com.example.core.market.DefaultSymbols
import com.example.core.market.MarketDataDiagnostic
import com.example.core.model.*
import com.example.data.local.dao.CandleDao
import com.example.data.local.dao.SymbolDao
import com.example.data.local.entity.CandleEntity
import com.example.data.local.entity.SymbolEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

class MarketDataRepository(
    val provider: DefaultMarketDataProvider,
    private val candleDao: CandleDao,
    private val symbolDao: SymbolDao
) {

    val providerDiagnostics: StateFlow<MarketDataDiagnostic> = provider.diagnosticInfo

    val symbols: Flow<List<SymbolInfo>> = symbolDao.getAllSymbols().map { list ->
        if (list.isEmpty()) {
            DefaultSymbols.SYMBOLS
        } else {
            list.map { it.toDomain() }
        }
    }

    suspend fun initializeSymbolsIfNeeded() = withContext(Dispatchers.IO) {
        val existing = symbolDao.getSymbol("XAUUSD")
        if (existing == null) {
            val entities = DefaultSymbols.SYMBOLS.map { it.toEntity() }
            symbolDao.insertSymbols(entities)
        }
    }

    suspend fun toggleFavorite(symbol: String, isFavorite: Boolean) = withContext(Dispatchers.IO) {
        symbolDao.updateFavorite(symbol, isFavorite)
    }

    /**
     * Cache-First Historical Candle Retrieval with Windowed Pagination:
     * 1. Query Room local cache for [from..to]
     * 2. If local cache contains sufficient contiguous data, return sanitized local slice
     * 3. Otherwise, fetch missing historical range from provider in bounded pages
     * 4. Sanitize and validate OHLC invariants, deduplicate, and persist to Room
     * 5. Return complete chronological list
     */
    suspend fun getCandles(
        symbol: String,
        timeframe: Timeframe,
        from: Long,
        to: Long,
        pageSize: Int = 500
    ): List<Candle> = withContext(Dispatchers.IO) {
        val intervalMillis = timeframe.minutes * 60_000L
        val expectedCount = ((to - from) / intervalMillis).coerceAtLeast(1L).toInt()

        // 1. Check local Room cache
        val localEntities = candleDao.getCandlesRange(symbol, timeframe.code, from, to)
        if (localEntities.size >= (expectedCount * 0.9).toInt().coerceAtLeast(50)) {
            val domainCandles = localEntities.map { it.toDomain() }
            return@withContext DataIntegrityValidator.sanitizeCandles(domainCandles)
        }

        // 2. Fetch from provider in bounded paginated windows
        val fetchedCandles = mutableListOf<Candle>()
        var currentWindowStart = from

        while (currentWindowStart < to && fetchedCandles.size < 5000) {
            val windowEnd = minOf(to, currentWindowStart + (intervalMillis * pageSize))
            val page = provider.getHistoricalCandles(symbol, timeframe, currentWindowStart, windowEnd)
            if (page.isEmpty()) break

            fetchedCandles.addAll(page)
            currentWindowStart = windowEnd + intervalMillis
        }

        // 3. Validate, deduplicate, and persist
        val sanitized = DataIntegrityValidator.sanitizeCandles(fetchedCandles)
        if (sanitized.isNotEmpty()) {
            candleDao.insertCandles(sanitized.map { it.toEntity() })
        }

        // 4. Return combined chronological dataset
        val finalEntities = candleDao.getCandlesRange(symbol, timeframe.code, from, to)
        if (finalEntities.isNotEmpty()) {
            DataIntegrityValidator.sanitizeCandles(finalEntities.map { it.toDomain() })
        } else {
            sanitized
        }
    }

    suspend fun clearCandlesCache(symbol: String, timeframe: Timeframe) = withContext(Dispatchers.IO) {
        candleDao.deleteCandles(symbol, timeframe.code)
    }

    fun observeTicks(symbol: String): Flow<Tick> = provider.observeTicks(symbol)

    private fun SymbolEntity.toDomain(): SymbolInfo = SymbolInfo(
        symbol = symbol,
        name = name,
        category = category,
        digits = digits,
        pipSize = pipSize,
        contractSize = contractSize,
        minLot = minLot,
        maxLot = maxLot,
        lotStep = lotStep,
        defaultSpreadPips = defaultSpreadPips,
        isFavorite = isFavorite
    )

    private fun SymbolInfo.toEntity(): SymbolEntity = SymbolEntity(
        symbol = symbol,
        name = name,
        category = category,
        digits = digits,
        pipSize = pipSize,
        contractSize = contractSize,
        minLot = minLot,
        maxLot = maxLot,
        lotStep = lotStep,
        defaultSpreadPips = defaultSpreadPips,
        isFavorite = isFavorite
    )

    private fun CandleEntity.toDomain(): Candle = Candle(
        symbol = symbol,
        timeframe = Timeframe.fromCode(timeframe),
        openTime = openTime,
        closeTime = closeTime,
        open = open,
        high = high,
        low = low,
        close = close,
        volume = volume,
        source = source
    )

    private fun Candle.toEntity(): CandleEntity = CandleEntity(
        symbol = symbol,
        timeframe = timeframe.code,
        openTime = openTime,
        closeTime = closeTime,
        open = open,
        high = high,
        low = low,
        close = close,
        volume = volume,
        source = source
    )
}
