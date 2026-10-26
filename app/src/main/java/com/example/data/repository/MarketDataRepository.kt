package com.example.data.repository

import com.example.core.market.DataIntegrityValidator
import com.example.core.market.HistoricalCandleIntegrity
import com.example.core.market.HistoricalCandleBoundary
import com.example.core.market.HistoricalCandleCoverage
import com.example.core.market.TwelveDataHistoricalProvider
import com.example.core.market.BiquoteHistoricalProvider
import com.example.core.market.DefaultMarketDataProvider
import com.example.core.market.DefaultSymbols
import com.example.core.market.MarketDataDiagnostic
import com.example.core.model.*
import com.example.data.local.dao.CandleDao
import com.example.data.local.dao.SymbolDao
import com.example.data.local.entity.CandleEntity
import com.example.data.local.entity.SymbolEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.yield
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

    // In-memory only. The user explicitly supplies their own provider key.
    // Do not cache or print credentials.
    private var twelveDataApiKey: String = ""
    private val twelveData = TwelveDataHistoricalProvider()
    private val keylessHistorical = BiquoteHistoricalProvider()

    fun configureTwelveDataKey(key: String) {
        require(key.length <= 256) { "API key is too long" }
        twelveDataApiKey = key.trim()
    }

    fun hasTwelveDataKey(): Boolean = twelveDataApiKey.isNotBlank()

    fun supportsHistoricalSymbol(symbol: String): Boolean =
        symbol == "BTCUSDT" || symbol == "ETHUSDT" || twelveData.supports(symbol)

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
        require(from >= 0 && from <= to) { "Invalid candle range" }
        require(to <= Long.MAX_VALUE - timeframe.minutes * 60_000L) { "Candle range overflow" }
        require(pageSize in 1..1000) { "pageSize must be between 1 and 1000" }
        val intervalMillis = timeframe.minutes * 60_000L
        require(intervalMillis > 0L) { "Invalid timeframe interval" }
        // Exclude the currently forming candle by its exchange open time,
        // not by subtracting an interval from now (which rejects valid history).
        require(HistoricalCandleBoundary.isClosedRange(
            to, System.currentTimeMillis(), intervalMillis
        )) { "Historical range includes an unfinished candle" }
        // Bound replay memory while fetching and validating one network page at a time.
        // Both boundaries are candle-open timestamps; reject partial windows.
        val weeklyInterval = 7L * 24 * 60 * 60 * 1000
        val weeklyOffset = 4L * 24 * 60 * 60 * 1000
        val offset = if (intervalMillis == weeklyInterval) weeklyOffset else 0L
        require(Math.floorMod(from - offset, intervalMillis) == 0L &&
            Math.floorMod(to - offset, intervalMillis) == 0L) {
            "Historical candle range must align to timeframe boundaries"
        }
        val requestedBars = (to - from) / intervalMillis + 1L
        require(requestedBars <= 20_000L) {
            "Historical range exceeds 20000 candles. Request a shorter range."
        }
        val isCrypto = symbol == "BTCUSDT" || symbol == "ETHUSDT"
        if (!isCrypto) {
            if (!twelveData.supports(symbol)) {
                throw java.io.IOException("No configured historical provider for $symbol")
            }
            // No credentials needed for normal chart viewing. An explicitly
            // configured Twelve Data key remains available as an alternative.
            // Do not fabricate bars to fill forex weekend/session gaps.
            val requestedKey = twelveDataApiKey
            val cachedForex = DataIntegrityValidator.sanitizeCandles(
                candleDao.getCandlesRange(symbol, timeframe.code, from, to)
                    .map { it.toDomain() }
            ).filter { candle ->
                candle.symbol == symbol && candle.timeframe == timeframe &&
                    candle.source in setOf("BIQUOTE_HISTORICAL", "TWELVE_DATA_HISTORICAL")
            }
            // A complete contiguous verified cache window needs no network.
            // Never assume that a sparse forex session is complete merely
            // because some candles were previously stored.
            if (HistoricalCandleCoverage.isComplete(
                    cachedForex, from, to, intervalMillis
                )) {
                return@withContext HistoricalCandleIntegrity.validate(
                    cachedForex, from, to + intervalMillis,
                    expectedSymbol = symbol, expectedTimeframe = timeframe
                )
            }
            // Forex/metals have market-session gaps. Fetch in bounded pages;
            // never fabricate bars and never return a partially successful range.
            val providerLimit = if (requestedKey.isNotBlank()) 1000 else 750
            val safePageSize = minOf(pageSize, providerLimit)
            val pages = ArrayList<Candle>(minOf(requestedBars.toInt(), 20_000))
            var cursor = from
            while (cursor <= to) {
                currentCoroutineContext().ensureActive()
                val remainingBars = (to - cursor) / intervalMillis + 1L
                // Keyless Biquote reserves two source bars for boundary handling.
                val maxPageBars = if (requestedKey.isNotBlank()) safePageSize else
                    minOf(safePageSize, 750 / when (timeframe.minutes) {
                        3 -> 3
                        120 -> 2
                        10080 -> 7
                        else -> 1
                    })
                require(maxPageBars > 0) { "Unsupported historical page size" }
                val barsInPage = minOf(remainingBars, maxPageBars.toLong())
                val end = cursor + (barsInPage - 1L) * intervalMillis
                val chunk = try {
                    if (requestedKey.isNotBlank()) {
                        twelveData.fetch(symbol, timeframe, cursor, end, requestedKey)
                    } else {
                        keylessHistorical.fetch(symbol, timeframe, cursor, end)
                    }
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    throw cancelled
                } catch (error: java.io.IOException) {
                    // Some providers signal a fully closed market as an empty
                    // result rather than an empty candle array. Do not hide
                    // transport failures, authorization errors or rate limits.
                    throw java.io.IOException(
                        "Historical page $cursor..$end failed for $symbol: ${error.message}", error
                    )
                }
                currentCoroutineContext().ensureActive()
                if (chunk.isEmpty()) {
                    // Market holidays/weekends may produce an empty window.
                    // Do not synthesize missing bars or abort a longer valid range.
                    if (end == to) break
                    cursor = end + intervalMillis
                    yield()
                    continue
                }
                val verified = HistoricalCandleIntegrity.validate(
                    chunk,
                    requestedFrom = cursor,
                    requestedTo = end + intervalMillis,
                    expectedSymbol = symbol,
                    expectedTimeframe = timeframe
                )
                require(verified.all { it.openTime in cursor..end }) {
                    "Historical provider returned candles outside requested page"
                }
                pages.addAll(verified)
                if (end == to) break
                cursor = end + intervalMillis
                yield()
            }
            val verified = HistoricalCandleIntegrity.validate(
                pages,
                requestedFrom = from,
                requestedTo = to + intervalMillis,
                expectedSymbol = symbol,
                expectedTimeframe = timeframe
            )
            if (verified.isEmpty()) {
                throw java.io.IOException("No verified historical candles for $symbol")
            }
            // Never hand replay duplicate or out-of-order timestamps across pages.
            require(verified.zipWithNext().all { (a, b) -> a.openTime < b.openTime }) {
                "Historical pages contain duplicate or unordered candle timestamps"
            }
            // Persist only provider-verified forex/metals OHLC. Repeated chart
            // navigation can then reuse a fully contiguous cached window without
            // another network round trip; session gaps still require provider checks.
            candleDao.insertCandles(verified.map { it.toEntity() })
            return@withContext verified
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

        // Validate once and reuse the same verified cache for full-window
        // returns and for page-by-page retrieval of missing data.
        val validCached = runCatching {
            HistoricalCandleIntegrity.validate(
                trustedLocal,
                requestedFrom = from,
                requestedTo = to + intervalMillis,
                expectedSymbol = symbol,
                expectedTimeframe = timeframe
            )
        }.getOrDefault(emptyList())
        if (HistoricalCandleCoverage.isComplete(validCached, from, to, intervalMillis)) {
            return@withContext validCached
        }
        val fetched = mutableListOf<Candle>()
        var cursor = from
        var cachedIndex = 0
        try {
            while (cursor <= to && fetched.size < 20_000) {
                currentCoroutineContext().ensureActive()
                val windowEnd = com.example.core.market.HistoricalPageWindow.end(
                    cursor, to, intervalMillis, pageSize
                ) ?: break
                // Both the cursor and validated cache are monotonically ordered.
                // Advance the cache index once instead of searching for each page.
                while (cachedIndex < validCached.size &&
                    validCached[cachedIndex].openTime < cursor) {
                    cachedIndex++
                }
                val startIndex = cachedIndex
                while (cachedIndex < validCached.size &&
                    validCached[cachedIndex].openTime <= windowEnd) {
                    cachedIndex++
                }
                val cachedPage = validCached.subList(startIndex, cachedIndex)
                if (HistoricalCandleCoverage.isComplete(cachedPage, cursor, windowEnd, intervalMillis)) {
                    cursor = cachedPage.last().openTime + intervalMillis
                    yield()
                    continue
                }
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
                // Give cancellation and other queued work a chance between pages.
                yield()
            }
        } catch (error: kotlinx.coroutines.CancellationException) {
            // Cancellation must propagate; never turn a cancelled request into cached success.
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
        // Do not reintroduce malformed cache entries when combining fresh pages.
        // Fresh network bars take precedence over older cache entries.
        val combined = DataIntegrityValidator.sanitizeCandles(
            (validCached + sanitized).associateBy { it.openTime }.values.toList()
        )
        if (combined.isEmpty() && isCrypto) {
            throw java.io.IOException("No verified Binance historical candles available for $symbol")
        }
        if (!HistoricalCandleCoverage.isComplete(combined, from, to, intervalMillis)) {
            throw java.io.IOException("Incomplete verified Binance history for $symbol")
        }
        // Completeness only verifies timestamps/count. Validate every returned
        // OHLC value and provenance before handing candles to the backtester.
        val verifiedCombined = HistoricalCandleIntegrity.validate(
            combined,
            requestedFrom = from,
            requestedTo = to + intervalMillis,
            expectedSymbol = symbol,
            expectedTimeframe = timeframe
        )
        require(verifiedCombined.all {
            it.source == "BINANCE_HISTORICAL" || it.source == "BINANCE_HISTORICAL_CACHED"
        }) { "Unverified historical source for $symbol" }
        // Cancellation after the final page must not commit stale history.
        currentCoroutineContext().ensureActive()
        // Persist only after the entire requested range has passed validation.
        if (sanitized.isNotEmpty()) {
            candleDao.insertCandles(sanitized.map { it.toEntity() })
        }
        verifiedCombined
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
