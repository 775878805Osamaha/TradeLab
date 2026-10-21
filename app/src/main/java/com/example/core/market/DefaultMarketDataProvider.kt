package com.example.core.market

import com.example.core.model.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

class DefaultMarketDataProvider(
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
) : MarketDataProvider, HistoricalDataProvider, StreamingMarketDataProvider {

    override val providerName: String = "TradeLab Binance Spot Market Data (BTCUSDT / ETHUSDT)"

    private val _isConnected = MutableStateFlow(false)
    override val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _connectionStatus = MutableStateFlow(ProviderConnectionStatus.DISCONNECTED)
    override val connectionStatus: StateFlow<ProviderConnectionStatus> = _connectionStatus.asStateFlow()

    private val _dataSourceType = MutableStateFlow(DataSourceType.STALE_DATA)
    override val dataSourceType: StateFlow<DataSourceType> = _dataSourceType.asStateFlow()

    private val _streamReconnectAttempts = MutableStateFlow(0)
    override val streamReconnectAttempts: StateFlow<Int> = _streamReconnectAttempts.asStateFlow()

    private val _validationErrorsCount = MutableStateFlow(0)
    val validationErrorsCount: StateFlow<Int> = _validationErrorsCount.asStateFlow()

    private val _lastSuccessfulUpdate = MutableStateFlow(0L)
    val lastSuccessfulUpdate: StateFlow<Long> = _lastSuccessfulUpdate.asStateFlow()

    private val _latencyMs = MutableStateFlow(0L)
    val latencyMs: StateFlow<Long> = _latencyMs.asStateFlow()

    private val _diagnosticInfo = MutableStateFlow(
        MarketDataDiagnostic(
            providerName = providerName,
            connectionStatus = ProviderConnectionStatus.DISCONNECTED,
            dataSourceType = DataSourceType.STALE_DATA,
            lastUpdateTimestamp = 0L,
            reconnectCount = 0,
            cachedCandlesCount = 0L,
            latestCandleTimestamp = 0L,
            latestTickTimestamp = 0L,
            validationErrorsCount = 0,
            isStale = true,
            approximateLatencyMs = 0L
        )
    )
    val diagnosticInfo: StateFlow<MarketDataDiagnostic> = _diagnosticInfo.asStateFlow()

    private val quoteEndpoints = QuoteEndpointPreference()

    private val latestTicks = ConcurrentHashMap<String, Tick>()
    private val tickFlows = ConcurrentHashMap<String, MutableSharedFlow<Tick>>()
    private val candleFlows = ConcurrentHashMap<String, MutableSharedFlow<Candle>>()
    private val rawStreamFlow = MutableSharedFlow<String>(replay = 1)
    private val subscribedSymbols = ConcurrentHashMap.newKeySet<String>()

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(6, TimeUnit.SECONDS)
        .readTimeout(6, TimeUnit.SECONDS)
        .build()

    private var benchmarkJob: Job? = null
    private var healthCheckJob: Job? = null
    private var binanceWsClient: BinanceWebSocketClient? = null


    init {
        // Do not fabricate an initial live quote before an exchange message arrives.
        // Initialize Binance WebSocket client
        binanceWsClient = BinanceWebSocketClient(
            onTickReceived = { tick ->
                emitTick(tick)
                _lastSuccessfulUpdate.value = tick.timestamp
                _dataSourceType.value = DataSourceType.LIVE_DATA
                _connectionStatus.value = ProviderConnectionStatus.CONNECTED
            },
            onCandleReceived = { candle ->
                emitCandle(candle)
            },
            onRawMessage = { msg ->
                rawStreamFlow.tryEmit(msg)
            },
            scope = scope
        )

        // Observe WebSocket connection status
        scope.launch {
            binanceWsClient?.connectionStatus?.collect { status ->
                // An open socket is not proof of a usable quote. The
                // health monitor owns CONNECTED/DEGRADED after first tick.
                if (status != ProviderConnectionStatus.CONNECTED ||
                    hasFreshVerifiedQuote()) {
                    _connectionStatus.value = status
                }
                updateDiagnostics()
            }
        }
        scope.launch {
            binanceWsClient?.reconnectAttempts?.collect { count ->
                _streamReconnectAttempts.value = count
                updateDiagnostics()
            }
        }
        scope.launch {
            binanceWsClient?.latencyMs?.collect { lat ->
                if (lat > 0) _latencyMs.value = lat
                updateDiagnostics()
            }
        }

        // Start health / stale check monitor
        startHealthCheck()
    }

    override suspend fun connect() {
        if (_isConnected.value) return
        _isConnected.value = true
        _connectionStatus.value = ProviderConnectionStatus.CONNECTING
        binanceWsClient?.start()
        startStreaming(subscribedSymbols.toList())
    }

    override suspend fun disconnect() {
        stopStreaming()
        binanceWsClient?.stop()
        _isConnected.value = false
        _connectionStatus.value = ProviderConnectionStatus.DISCONNECTED
        updateDiagnostics()
    }

    override suspend fun startStreaming(symbols: List<String>) {
        benchmarkJob?.cancel()
        benchmarkJob = scope.launch {
            // Each symbol polls independently: a blocked ETH request must not
            // delay the next BTC refresh (and vice versa).
            for (symbol in listOf("BTCUSDT", "ETHUSDT")) {
                launch {
                    while (isActive) {
                        fetchLiveCryptoQuote(symbol)
                        delay(3000)
                    }
                }
            }
        }
    }

    override suspend fun stopStreaming() {
        benchmarkJob?.cancel()
        benchmarkJob = null
    }

    override fun observeRawStream(): Flow<String> = rawStreamFlow.asSharedFlow()

    override suspend fun subscribe(symbol: String) {
        val sym = normalizeSymbol(symbol)
        subscribedSymbols.add(sym)
        if (!_isConnected.value) {
            connect()
        }
    }

    override suspend fun unsubscribe(symbol: String) {
        val sym = normalizeSymbol(symbol)
        subscribedSymbols.remove(sym)
    }

    override suspend fun getLatestTick(symbol: String): Tick? {
        val sym = normalizeSymbol(symbol)
        return latestTicks[sym]
    }

    override fun observeTicks(symbol: String): Flow<Tick> {
        val sym = normalizeSymbol(symbol)
        val flow = tickFlows.getOrPut(sym) {
            latestMarketFlow()
        }
        latestTicks[sym]?.let { flow.tryEmit(it) }
        return flow.asSharedFlow()
    }

    override fun observeCandles(symbol: String, timeframe: Timeframe): Flow<Candle> {
        val sym = normalizeSymbol(symbol)
        val key = "${sym}_${timeframe.code}"
        return candleFlows.getOrPut(key) {
            latestMarketFlow()
        }.asSharedFlow()
    }

    fun setDataSourceType(type: DataSourceType) {
        _dataSourceType.value = type
        updateDiagnostics()
    }

    fun emitTick(tick: Tick) {
        val sym = normalizeSymbol(tick.symbol)
        val normalizedTick = tick.copy(symbol = sym)
        val validation = DataIntegrityValidator.validateTick(normalizedTick)
        if (!validation.isValid) {
            _validationErrorsCount.update { it + 1 }
            return
        }
        latestTicks[sym] = normalizedTick
        tickFlows[sym]?.tryEmit(normalizedTick)
        _lastSuccessfulUpdate.value = normalizedTick.timestamp
    }

    fun emitCandle(candle: Candle) {
        val sym = normalizeSymbol(candle.symbol)
        val normalizedCandle = candle.copy(symbol = sym)
        val validation = DataIntegrityValidator.validateCandle(normalizedCandle)
        if (!validation.isValid) {
            _validationErrorsCount.update { it + 1 }
            return
        }
        val key = "${sym}_${candle.timeframe.code}"
        candleFlows[key]?.tryEmit(normalizedCandle)
    }

    /**
     * Query verified Binance Spot bookTicker endpoints. Mobile networks may block
     * the primary API host even while historical candles are cached.
     * Only validated exchange bid/ask data can unlock paper trading.
     */
    private suspend fun fetchLiveCryptoQuote(symbol: String): Boolean = withContext(Dispatchers.IO) {
        var received = false
        for (host in quoteEndpoints.orderedHosts(symbol)) {
            ensureActive()
            try {
                val url = okhttp3.HttpUrl.Builder()
                    .scheme("https")
                    .host(host)
                    .addPathSegments("api/v3/ticker/bookTicker")
                    .addQueryParameter("symbol", symbol)
                    .build()
                val request = Request.Builder().url(url)
                    .header("User-Agent", "TradeLab/2.0")
                    .build()
                var valid = false
                httpClient.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val body = response.body?.string()
                        if (body != null) {
                            val item = org.json.JSONObject(body)
                            if (item.optString("symbol") == symbol) {
                                val bid = item.getDouble("bidPrice")
                                val ask = item.getDouble("askPrice")
                                val tick = Tick(
                                    symbol = symbol,
                                    bid = bid,
                                    ask = ask,
                                    last = (bid + ask) / 2.0,
                                    timestamp = System.currentTimeMillis(),
                                    source = "BINANCE_REST_POLL"
                                )
                                if (DataIntegrityValidator.validateTick(tick).isValid) {
                                    emitTick(tick)
                                    rawStreamFlow.tryEmit(body)
                                    _dataSourceType.value = DataSourceType.LIVE_DATA
                                    _connectionStatus.value = ProviderConnectionStatus.CONNECTED
                                    valid = true
                                    received = true
                                }
                            }
                        }
                    }
                }
                if (valid) {
                    quoteEndpoints.recordSuccess(symbol, host)
                    break
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Try another official Binance endpoint; never invent prices.
            }
        }
        received
    }

    override suspend fun getHistoricalCandles(
        symbol: String,
        timeframe: Timeframe,
        from: Long,
        to: Long
    ): List<Candle> {
        return loadHistoricalRange(symbol, timeframe, from, to)
    }

    override suspend fun loadHistoricalRange(
        symbol: String,
        timeframe: Timeframe,
        fromTimestamp: Long,
        toTimestamp: Long
    ): List<Candle> = withContext(Dispatchers.IO) {
        val sym = normalizeSymbol(symbol)
        if (sym == "BTCUSDT" || sym == "ETHUSDT") {
            require(fromTimestamp <= toTimestamp) { "Invalid historical date range" }
            val interval = timeframe.displayName.lowercase().let {
                when (timeframe) {
                    Timeframe.D1 -> "1d"
                    Timeframe.W1 -> "1w"
                    else -> it
                }
            }
            val results = mutableListOf<Candle>()
            var cursor = fromTimestamp
            val step = timeframe.minutes * 60_000L
            while (cursor <= toTimestamp) {
                // Use the same official endpoint failover as live quotes.
                // A blocked primary API host must not break historical replay.
                var batch: List<Candle>? = null
                var lastFailure: Exception? = null
                for (host in quoteEndpoints.orderedHosts(sym)) {
                    ensureActive()
                    try {
                        val url = okhttp3.HttpUrl.Builder()
                            .scheme("https").host(host)
                            .addPathSegments("api/v3/klines")
                            .addQueryParameter("symbol", sym)
                            .addQueryParameter("interval", interval)
                            .addQueryParameter("startTime", cursor.toString())
                            .addQueryParameter("endTime", toTimestamp.toString())
                            .addQueryParameter("limit", "1000")
                            .build()
                        val request = Request.Builder().url(url).build()
                        val loaded = httpClient.newCall(request).execute().use { response ->
                            if (!response.isSuccessful) {
                                throw java.io.IOException("Binance historical request failed: HTTP ${response.code}")
                            }
                            val body = response.body?.string()
                                ?: throw java.io.IOException("Empty Binance historical response")
                    val json = JSONArray(body)
                    (0 until json.length()).map { index ->
                        val row = json.getJSONArray(index)
                        Candle(
                            symbol = sym, timeframe = timeframe,
                            openTime = row.getLong(0),
                            closeTime = row.getLong(6) + 1L,
                            open = row.getString(1).toDouble(),
                            high = row.getString(2).toDouble(),
                            low = row.getString(3).toDouble(),
                            close = row.getString(4).toDouble(),
                            volume = row.getString(5).toDouble(),
                            source = "BINANCE_HISTORICAL"
                        )
                    }
                        }
                        batch = loaded
                        quoteEndpoints.recordSuccess(sym, host)
                        break
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (failure: Exception) {
                        lastFailure = failure
                    }
                }
                val verifiedBatch = batch ?: throw java.io.IOException(
                    "All Binance historical endpoints failed for $sym", lastFailure
                )
                if (verifiedBatch.isEmpty()) break
                results.addAll(verifiedBatch.filter { it.isValid() })
                val next = verifiedBatch.last().openTime + step
                if (next <= cursor) break
                cursor = next
                if (verifiedBatch.size < 1000) break
            }
            return@withContext DataIntegrityValidator.sanitizeCandles(results)
        }
        // Forex and XAUUSD require a separate licensed/verified data provider.
        // Never generate synthetic candles in production market mode.
        throw java.io.IOException("No verified live market feed configured for $sym")

    }

    private fun hasFreshVerifiedQuote(now: Long = System.currentTimeMillis()): Boolean =
        latestTicks.values.any { tick ->
            tick.symbol in setOf("BTCUSDT", "ETHUSDT") &&
                tick.source in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL") &&
                now - tick.timestamp in 0..15_000L
        }

    private fun startHealthCheck() {
        healthCheckJob?.cancel()
        healthCheckJob = scope.launch {
            while (isActive) {
                delay(3000)
                val fresh = hasFreshVerifiedQuote()
                _dataSourceType.value = if (fresh) DataSourceType.LIVE_DATA
                    else DataSourceType.STALE_DATA
                if (_isConnected.value) {
                    _connectionStatus.value = if (fresh) ProviderConnectionStatus.CONNECTED
                        else ProviderConnectionStatus.DEGRADED
                }
                updateDiagnostics()
            }
        }
    }

    private fun updateDiagnostics() {
        val now = System.currentTimeMillis()
        val elapsed = now - _lastSuccessfulUpdate.value
        val isStale = !hasFreshVerifiedQuote(now)

        _diagnosticInfo.value = MarketDataDiagnostic(
            providerName = providerName,
            connectionStatus = _connectionStatus.value,
            dataSourceType = _dataSourceType.value,
            lastUpdateTimestamp = _lastSuccessfulUpdate.value,
            reconnectCount = _streamReconnectAttempts.value,
            cachedCandlesCount = latestTicks.size.toLong(),
            latestCandleTimestamp = now,
            latestTickTimestamp = _lastSuccessfulUpdate.value,
            validationErrorsCount = _validationErrorsCount.value,
            isStale = isStale,
            approximateLatencyMs = _latencyMs.value
        )
    }

    private fun normalizeSymbol(symbol: String): String {
        return MarketSymbolRegistry.normalizeSymbol(symbol)
    }
}
