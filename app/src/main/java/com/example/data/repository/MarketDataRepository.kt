package com.example.data.repository

import com.example.core.market.DataIntegrityValidator
import com.example.core.market.HistoricalCandleIntegrity
import com.example.core.market.HistoricalCandleCoverage
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
        require(from >= 0 && from < to) { "Invalid candle range" }
        require(to <= Long.MAX_VALUE - timeframe.minutes * 60_000L) { "Candle range overflow" }
        require(pageSize in 1..1000) { "pageSize must be between 1 and 1000" }
        val intervalMillis = timeframe.minutes * 60_000L
        // Never backtest the still-forming exchange candle.
        require(to <= System.currentTimeMillis() - intervalMillis) {
            "Historical range includes an unfinished candle"
        }
        // Limit the returned list to keep replay memory bounded. Fetch pages lazily.
        val requestedBars = (to - from) / intervalMillis + 1L
        require(requestedBars <= 20_000L) {
            "Historical range exceeds 20000 candles. Request a shorter range."
        }
        val isCrypto = symbol == "BTCUSDT" || symbol == "ETHUSDT"
        if (!isCrypto) {
            throw java.io.IOException("No verified live/historical provider for $symbol. Demo candles are disabled.")
        }
        val local = DataIntegrityValidator.sanitizeCandles(
            candleDao.getCandlesRange(symbol, timeframe.code, from, to).map { it.toDomain() }
        )
        // A synthetic historical candle must never be treated as verified exchange data.
        val trustedLocal = local.filter { candle ->
            candle.symbol.equals(symbol, ignoreCase = true) &&
                candle.timeframe == timeframe &&
                (candle.source == "BINANCE_HISTORICAL" || candle.source == "BINANCE_HISTORICAL_CACHED")
        }

        // A candle cache is complete only when every expected bar exists.
        // Never mistake sparse history for a complete backtest window.
        val fullyCovered = HistoricalCandleCoverage.isComplete(
            trustedLocal, from, to, intervalMillis
        )
        if (fullyCovered) {
            return@withContext trustedLocal
        }

        val fetched = mutableListOf<Candle>()
        var cursor = from
        try {
            while (cursor <= to && fetched.size < 20_000) {
                val windowEnd = minOf(to, cursor + intervalMillis * (pageSize - 1L))
                val page = provider.getHistoricalCandles(symbol, timeframe, cursor, windowEnd)
                if (page.isEmpty()) break
                // A page must not silently cross its requested boundary.
                require(page.all { it.openTime in cursor..windowEnd }) {
                    "Historical provider returned candles outside page window"
                }
                // Do not advance past a missing or truncated page. A complete
                // historical window is required for deterministic replay.
                val verifiedPage = HistoricalCandleIntegrity.validate(
                    page,
                    requestedFrom = cursor,
                    requestedTo = windowEnd + intervalMillis,
                    expectedSource = "BINANCE_HISTORICAL",
                    expectedSymbol = symbol,
                    expectedTimeframe = timeframe
                )
                require(HistoricalCandleCoverage.isComplete(
                    verifiedPage, cursor, windowEnd, intervalMillis
                )) { "Incomplete Binance historical page for $symbol" }
                fetched.addAll(verifiedPage)
                val lastOpen = verifiedPage.maxOf { it.openTime }
                val next = lastOpen + intervalMillis
                if (next <= cursor) break
                cursor = next
            }
        } catch (error: kotlinx.coroutines.CancellationException) {
            // Cancellation must propagate; never turn a cancelled request into cached success.
            throw error
        } catch (error: Exception) {
            throw error
        }

        // Fail closed on malformed or unverified network history before it reaches Room.
        // Provider pagination may include the final candle opening at 'to'.
        val sanitized = HistoricalCandleIntegrity.validate(
            fetched,
            requestedFrom = from,
            requestedTo = to + intervalMillis,
            expectedSource = "BINANCE_HISTORICAL",
            expectedSymbol = symbol,
            expectedTimeframe = timeframe
        )
        // Fresh network bars take precedence over older cache entries with the same timestamp.
        val combined = DataIntegrityValidator.sanitizeCandles(
            (trustedLocal + sanitized).associateBy { it.openTime }.values.toList()
        )
        if (combined.isEmpty() && isCrypto) {
            throw java.io.IOException("No verified Binance historical candles available for $symbol")
        }
        if (!HistoricalCandleCoverage.isComplete(combined, from, to, intervalMillis)) {
            throw java.io.IOException("Incomplete verified Binance history for $symbol")
        }
        // Persist only after the entire requested range has passed validation.
        if (sanitized.isNotEmpty()) {
            candleDao.insertCandles(sanitized.map { it.toEntity() })
        }
        combined
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
