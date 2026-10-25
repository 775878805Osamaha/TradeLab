package com.example.feature.chart

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.indicators.*
import com.example.core.market.CandleAggregator
import com.example.core.model.*
import com.example.data.local.dao.DrawingDao
import com.example.data.repository.MarketDataRepository
import com.example.data.repository.TradingRepository
import com.example.feature.chart.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class ChartUiState(
    val selectedSymbol: String = "XAUUSD",
    val selectedTimeframe: Timeframe = Timeframe.M15,
    val candles: List<Candle> = emptyList(),
    val latestTick: Tick? = null,
    val openPositions: List<Position> = emptyList(),
    val pendingOrders: List<Order> = emptyList(),
    val historicalTrades: List<TradeJournalEntry> = emptyList(),
    val dataSourceType: DataSourceType = DataSourceType.LIVE_DATA,
    val activeDrawingTool: DrawingTool = DrawingTool.NONE,
    val drawings: List<ChartDrawing> = emptyList(),
    val indicatorSettings: IndicatorSettings = IndicatorSettings(),
    val smaValues: List<Double?> = emptyList(),
    val emaValues: List<Double?> = emptyList(),
    val bollingerValues: List<BollingerBandsResult?> = emptyList(),
    val vwapValues: List<Double> = emptyList(),
    val rsiValues: List<Double?> = emptyList(),
    val macdValues: List<MacdResult?> = emptyList(),
    val atrValues: List<Double?> = emptyList(),
    val isCrosshairActive: Boolean = false,
    val isVolumeVisible: Boolean = true,
    val selectedTradeForDetail: TradeJournalEntry? = null,
    val resetViewTrigger: Long = 0L,
    val isLoading: Boolean = false,
    val chartHistoryBars: Int = 250,
    val isLoadingOlderHistory: Boolean = false,
    val olderHistoryError: String? = null,
    val candleLoadError: String? = null,
    val connectionDiagnostic: String = "لم يتم اختبار الاتصال بعد",
    val message: String? = null
)

class ChartViewModel(
    private val marketDataRepository: MarketDataRepository,
    private val tradingRepository: TradingRepository,
    private val drawingDao: DrawingDao? = null
) : ViewModel() {

    private val _uiState = MutableStateFlow(ChartUiState())
    val uiState: StateFlow<ChartUiState> = _uiState.asStateFlow()

    private var candleLoadJob: Job? = null
    private var tickJob: Job? = null
    private var klineRefreshJob: Job? = null
    private var klineStreamJob: Job? = null
    private var drawingJob: Job? = null
    private var indicatorJob: Job? = null
    private var allPositions: List<Position> = emptyList()
    private var allPendingOrders: List<Order> = emptyList()
    private var allHistoricalTrades: List<TradeJournalEntry> = emptyList()

    init {
        loadCandlesForCurrentSymbol()
        observeAccountPositions()
        observePendingOrders()
        observeHistoricalTrades()
        observeDataSourceType()
        observeConnectionDiagnostics()
        observeDrawings()
    }

    private fun observeConnectionDiagnostics() {
        viewModelScope.launch {
            marketDataRepository.providerDiagnostics.collect { diagnostic ->
                _uiState.update { it.copy(connectionDiagnostic = diagnostic.lastHttpDiagnostic) }
            }
        }
    }

    fun configureHistoricalProviderKey(key: String) {
        marketDataRepository.configureTwelveDataKey(key)
        if (_uiState.value.selectedSymbol !in setOf("BTCUSDT", "ETHUSDT")) {
            loadCandlesForCurrentSymbol()
        }
    }

    fun hasHistoricalProviderKey(): Boolean = marketDataRepository.hasTwelveDataKey()

    /** Adjust the real OHLC history depth without changing the current instrument. */
    fun setChartHistoryBars(bars: Int) {
        require(bars in setOf(100, 250, 500, 750)) { "Unsupported chart history depth" }
        if (_uiState.value.chartHistoryBars == bars) return
        _uiState.update { it.copy(chartHistoryBars = bars, isLoading = true, candleLoadError = null, olderHistoryError = null) }
        loadCandlesForCurrentSymbol()
    }

    /**
     * Append only authentic older OHLC bars; retain the current chart on a
     * provider failure. The 20k cap is a memory safety limit, not a promise
     * that every historical source has this much verified data.
     */
    fun loadOlderChartHistory() {
        val snapshot = _uiState.value
        if (snapshot.isLoading || snapshot.isLoadingOlderHistory ||
            snapshot.candles.isEmpty() || snapshot.candles.size >= 20_000) return
        val symbol = snapshot.selectedSymbol
        val timeframe = snapshot.selectedTimeframe
        val oldest = snapshot.candles.first().openTime
        val interval = timeframe.minutes * 60_000L
        if (oldest < interval) return
        _uiState.update { it.copy(isLoadingOlderHistory = true, olderHistoryError = null) }
        viewModelScope.launch {
            try {
                val pageEnd = oldest - interval
                val pageFrom = (pageEnd - interval * 99L).coerceAtLeast(0L)
                // A large provider window may be incomplete around holidays.
                // Retry smaller aligned windows before reporting unavailable history.
                var verified = emptyList<Candle>()
                var lastPageFailure: Exception? = null
                for (depth in listOf(100, 40, 10, 2)) {
                    val candidateFrom = (pageEnd - interval * (depth - 1L)).coerceAtLeast(0L)
                    try {
                        val page = marketDataRepository.getCandles(
                            symbol, timeframe, candidateFrom, pageEnd
                        )
                        val candidate = CandleAggregator.aggregate(page, timeframe)
                        if (candidate.isNotEmpty()) {
                            verified = candidate
                            break
                        }
                    } catch (cancelled: kotlinx.coroutines.CancellationException) {
                        throw cancelled
                    } catch (error: Exception) {
                        lastPageFailure = error
                    }
                }
                if (verified.isEmpty() && lastPageFailure != null) throw lastPageFailure
                if (verified.any { it.symbol != symbol || it.timeframe != timeframe ||
                        it.openTime >= oldest }) {
                    throw IllegalStateException("Historical page contains mismatched or future candles")
                }
                if (_uiState.value.selectedSymbol != symbol ||
                    _uiState.value.selectedTimeframe != timeframe) return@launch
                val existing = _uiState.value.candles
                val merged = (verified + existing).distinctBy { it.openTime }
                    .sortedBy { it.openTime }.takeLast(20_000)
                _uiState.update {
                    it.copy(candles = merged, isLoadingOlderHistory = false,
                        olderHistoryError = if (merged.size == existing.size)
                            "لا تتوفر شموع تاريخية أقدم مؤكدة من المصدر" else null)
                }
                if (merged.size != existing.size) {
                    recalculateIndicators(merged, _uiState.value.indicatorSettings)
                }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (_uiState.value.selectedSymbol == symbol &&
                    _uiState.value.selectedTimeframe == timeframe) {
                    _uiState.update { it.copy(isLoadingOlderHistory = false,
                        olderHistoryError = (error.message ?: "تعذر تحميل الشموع الأقدم").take(160)) }
                }
            }
        }
    }

    fun retryChartHistory() {
        _uiState.update { it.copy(isLoading = true, candleLoadError = null) }
        loadCandlesForCurrentSymbol()
    }


    fun selectSymbol(symbol: String) {
        if (_uiState.value.selectedSymbol == symbol) return
        // Prevent unsupported instruments from retaining a previous exchange quote.
        // The history loader will show an explicit unavailable-source message.
        candleLoadJob?.cancel()
        tickJob?.cancel()
        klineRefreshJob?.cancel()
        klineStreamJob?.cancel()
        indicatorJob?.cancel()
        _uiState.update {
            it.copy(
                selectedSymbol = symbol, isLoading = true, candleLoadError = null,
                latestTick = null, candles = emptyList(),
                openPositions = allPositions.filter { position -> position.symbol == symbol },
                pendingOrders = allPendingOrders.filter { order -> order.symbol == symbol },
                historicalTrades = allHistoricalTrades.filter { trade -> trade.symbol == symbol },
                smaValues = emptyList(), emaValues = emptyList(),
                bollingerValues = emptyList(), vwapValues = emptyList(),
                rsiValues = emptyList(), macdValues = emptyList(), atrValues = emptyList(),
                drawings = emptyList()
            )
        }
        loadCandlesForCurrentSymbol()
        observeDrawings()
    }

    fun selectTimeframe(timeframe: Timeframe) {
        if (_uiState.value.selectedTimeframe == timeframe) return
        // Keep the existing bid/ask subscription: a timeframe change does not
        // change the instrument and should not disconnect its live quote.
        klineRefreshJob?.cancel()
        klineStreamJob?.cancel()
        indicatorJob?.cancel()
        _uiState.update {
            it.copy(
                selectedTimeframe = timeframe, isLoading = true, candleLoadError = null,
                candles = emptyList(), smaValues = emptyList(), emaValues = emptyList(),
                bollingerValues = emptyList(), vwapValues = emptyList(),
                rsiValues = emptyList(), macdValues = emptyList(), atrValues = emptyList(),
                drawings = emptyList()
            )
        }
        loadCandlesForCurrentSymbol()
        observeDrawings()
    }

    fun updateIndicatorSettings(settings: IndicatorSettings) {
        _uiState.update { it.copy(indicatorSettings = settings) }
        recalculateIndicators(_uiState.value.candles, settings)
    }

    fun toggleCrosshair() {
        _uiState.update { state ->
            val enabled = !state.isCrosshairActive
            state.copy(
                isCrosshairActive = enabled,
                activeDrawingTool = if (enabled) DrawingTool.NONE else state.activeDrawingTool
            )
        }
    }

    fun toggleVolume() {
        _uiState.update { it.copy(isVolumeVisible = !it.isVolumeVisible) }
    }

    fun triggerResetView() {
        _uiState.update { it.copy(resetViewTrigger = System.currentTimeMillis()) }
    }

    fun setDrawingTool(tool: DrawingTool) {
        _uiState.update { state ->
            val next = if (state.activeDrawingTool == tool) DrawingTool.NONE else tool
            state.copy(activeDrawingTool = next, isCrosshairActive = false)
        }
    }

    fun addDrawing(drawing: ChartDrawing) {
        val sym = _uiState.value.selectedSymbol
        val tf = _uiState.value.selectedTimeframe.code
        val drawingWithMeta = drawing.copy(symbol = sym, timeframe = tf)

        viewModelScope.launch {
            if (drawingDao != null) {
                withContext(Dispatchers.IO) {
                    drawingDao.insertDrawing(drawingWithMeta.toEntity())
                }
            } else {
                _uiState.update { state ->
                    if (state.selectedSymbol == sym && state.selectedTimeframe.code == tf) {
                        state.copy(drawings = state.drawings + drawingWithMeta)
                    } else state
                }
            }
        }
        _uiState.update { it.copy(activeDrawingTool = DrawingTool.NONE) }
    }

    fun deleteDrawing(id: Long) {
        viewModelScope.launch {
            if (drawingDao != null) {
                withContext(Dispatchers.IO) {
                    drawingDao.deleteDrawing(id)
                }
            } else {
                _uiState.update { state ->
                    state.copy(drawings = state.drawings.filter { d -> d.id != id })
                }
            }
        }
    }

    fun clearDrawings() {
        val sym = _uiState.value.selectedSymbol
        val tf = _uiState.value.selectedTimeframe.code
        viewModelScope.launch {
            if (drawingDao != null) {
                withContext(Dispatchers.IO) {
                    drawingDao.clearDrawings(sym, tf)
                }
            } else {
                _uiState.update { state ->
                    if (state.selectedSymbol == sym && state.selectedTimeframe.code == tf) {
                        state.copy(drawings = emptyList())
                    } else state
                }
            }
        }
    }

    fun selectTradeForDetail(trade: TradeJournalEntry?) {
        _uiState.update { it.copy(selectedTradeForDetail = trade) }
    }

    fun modifyPositionSlTp(positionId: Long, stopLoss: Double?, takeProfit: Double?) {
        viewModelScope.launch {
            val res = tradingRepository.modifyPosition(positionId, stopLoss, takeProfit)
            res.onSuccess {
                _uiState.update { it.copy(message = "تم تحديث مستويات الوقف والهدف بنجاح") }
            }.onFailure { err ->
                _uiState.update { it.copy(message = err.message ?: "فشل تحديث المستويات") }
            }
        }
    }

    fun quickOrder(side: OrderSide, volume: Double = 0.01, stopLoss: Double? = null, takeProfit: Double? = null) {
        if (!volume.isFinite() || volume <= 0.0) {
            _uiState.update { it.copy(message = "حجم الصفقة يجب أن يكون رقمًا موجبًا وصالحًا") }
            return
        }
        val state = _uiState.value
        val tick = state.latestTick
        if (tick == null || tick.symbol != state.selectedSymbol ||
            tick.source !in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL") ||
            System.currentTimeMillis() - tick.timestamp !in 0..15_000L ||
            !tick.bid.isFinite() || !tick.ask.isFinite() ||
            tick.bid <= 0.0 || tick.ask < tick.bid) {
            _uiState.update { it.copy(message = "لا يمكن تنفيذ أمر بسعر غير متصل أو قديم") }
            return
        }
        val entry = if (side == OrderSide.BUY) tick.ask else tick.bid
        if ((stopLoss != null && (!stopLoss.isFinite() || stopLoss <= 0.0 ||
                (if (side == OrderSide.BUY) stopLoss >= entry else stopLoss <= entry))) ||
            (takeProfit != null && (!takeProfit.isFinite() || takeProfit <= 0.0 ||
                (if (side == OrderSide.BUY) takeProfit <= entry else takeProfit >= entry)))) {
            _uiState.update { it.copy(message = "وقف الخسارة أو جني الربح غير صالح بالنسبة لسعر الدخول") }
            return
        }
        viewModelScope.launch {
            val account = tradingRepository.selectedAccount.first()
            if (account == null) {
                _uiState.update { it.copy(message = "لم يتم تحديد حساب افتراضي") }
                return@launch
            }
            val result = tradingRepository.executeMarketOrder(
                accountId = account.id,
                symbol = state.selectedSymbol,
                side = side,
                volume = volume,
                tick = tick,
                stopLoss = stopLoss,
                takeProfit = takeProfit
            )
            result.onSuccess {
                _uiState.update { it.copy(message = "تم فتح أمر ${if (side == OrderSide.BUY) "شراء" else "بيع"} $volume لوت بنجاح") }
            }.onFailure { err ->
                _uiState.update { it.copy(message = err.message ?: "فشل تنفيذ الأمر") }
            }
        }
    }

    private fun loadCandlesForCurrentSymbol() {
        val symbol = _uiState.value.selectedSymbol
        val tf = _uiState.value.selectedTimeframe
        val requestedBars = _uiState.value.chartHistoryBars

        candleLoadJob?.cancel()
        candleLoadJob = viewModelScope.launch {
            if (!marketDataRepository.supportsHistoricalSymbol(symbol)) {
                if (_uiState.value.selectedSymbol == symbol && _uiState.value.selectedTimeframe == tf) {
                    _uiState.update {
                        it.copy(candles = emptyList(), latestTick = null, isLoading = false,
                            candleLoadError = "لا يوجد مصدر تاريخي مدعوم لهذا الرمز.")
                    }
                }
                return@launch
            }
            val now = System.currentTimeMillis()
            val interval = tf.minutes * 60_000L
            // The repository intentionally rejects an unfinished Binance bar.
            // Request only fully closed candle OPEN timestamps, aligned to UTC
            // (including Monday UTC alignment for weekly bars).
            val lastClosedOpen = com.example.core.market.HistoricalCandleBoundary
                .currentOpen(now, interval) - interval
            val from = (lastClosedOpen - interval * (requestedBars - 1L)).coerceAtLeast(0L)

            try {
                // Start live subscription even if historical REST loading fails.
                if (symbol in setOf("BTCUSDT", "ETHUSDT")) subscribeToTicks(symbol)
                // A provider may have fewer verified bars than the requested history.
                // Retry smaller, recent windows instead of replacing the entire chart
                // with an error. Never fabricate missing OHLC data.
                var rawCandles = emptyList<com.example.core.model.Candle>()
                var lastHistoryError: Exception? = null
                for (depth in listOf(requestedBars, 100, 40, 10).distinct().filter { it <= requestedBars }) {
                    val attemptFrom = (lastClosedOpen - interval * (depth - 1L)).coerceAtLeast(0L)
                    try {
                        val fetched = marketDataRepository.getCandles(symbol, tf, attemptFrom, lastClosedOpen)
                        if (fetched.isNotEmpty()) {
                            rawCandles = fetched
                            break
                        }
                    } catch (cancelled: kotlinx.coroutines.CancellationException) {
                        throw cancelled
                    } catch (error: Exception) {
                        lastHistoryError = error
                    }
                }
                if (rawCandles.isEmpty() && lastHistoryError != null) throw lastHistoryError
                val aggregated = CandleAggregator.aggregate(rawCandles, tf)
                if (aggregated.any { candle ->
                    candle.symbol != symbol || candle.timeframe != tf ||
                    candle.openTime > lastClosedOpen ||
                    !candle.open.isFinite() || !candle.high.isFinite() ||
                    !candle.low.isFinite() || !candle.close.isFinite() ||
                    candle.low <= 0.0 || candle.high < candle.low ||
                    candle.open !in candle.low..candle.high ||
                    candle.close !in candle.low..candle.high ||
                    !candle.volume.isFinite() || candle.volume < 0.0
                }) {
                    throw IllegalStateException("Invalid verified chart candle data")
                }
                // Reject malformed, mixed or future OHLC history rather than showing
                // potentially misleading prices in the chart.
                if (aggregated.isNotEmpty()) {
                    val audit = com.example.core.market.HistoricalDataAudit.inspect(aggregated, now)
                    if (!audit.safeForBacktest) {
                        throw IllegalStateException(
                            "Historical OHLC integrity check failed: " +
                                audit.issues.take(2).joinToString("; ")
                        )
                    }
                }
                // Ignore responses that arrive after the user changes symbol or timeframe.
                if (_uiState.value.selectedSymbol != symbol || _uiState.value.selectedTimeframe != tf ||
                    _uiState.value.chartHistoryBars != requestedBars) return@launch
                _uiState.update { it.copy(candles = aggregated, isLoading = false, candleLoadError = if (aggregated.isEmpty()) "لا تتوفر شموع مؤكدة لهذا الرمز والفاصل الزمني. حاول مجددًا." else null, message = null) }
                recalculateIndicators(aggregated, _uiState.value.indicatorSettings)
                if (symbol in setOf("BTCUSDT", "ETHUSDT")) {
                    startKlineRefresh(symbol, tf)
                    startKlineStream(symbol, tf)
                } else {
                    // Twelve Data is historical-only here; do not open Binance
                    // streaming endpoints or continuously consume API quota.
                    klineRefreshJob?.cancel()
                    klineStreamJob?.cancel()
                }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (_uiState.value.selectedSymbol == symbol && _uiState.value.selectedTimeframe == tf) {
                    _uiState.update {
                        it.copy(
                            // A transient provider failure must not erase verified candles
                            // already displayed for this symbol/timeframe.
                            candles = if (it.candles.firstOrNull()?.symbol == symbol &&
                                it.candles.firstOrNull()?.timeframe == tf) it.candles else emptyList(),
                            isLoading = false,
                            // Report the actual failure instead of assuming that
                            // every historical-data error is an internet outage.
                            candleLoadError = "فشل تحميل شموع ${if (symbol in setOf("BTCUSDT", "ETHUSDT")) "Binance" else "مصدر الذهب والفوركس"}: ${error.javaClass.simpleName}: " +
                                (error.cause?.message ?: error.message ?: "سبب غير معروف").take(220))
                    }
                }
            }
        }
    }

    /**
     * Consume real Binance 1-minute kline stream. For larger timeframes,
     * REST polling remains the authoritative OHLCV update mechanism.
     */
    private fun startKlineStream(symbol: String, timeframe: Timeframe) {
        klineStreamJob?.cancel()
        if (timeframe != Timeframe.M1 || (symbol != "BTCUSDT" && symbol != "ETHUSDT")) return
        klineStreamJob = viewModelScope.launch {
            marketDataRepository.provider.observeCandles(symbol, timeframe).collect { candle ->
                if (_uiState.value.selectedSymbol != symbol ||
                    _uiState.value.selectedTimeframe != timeframe) return@collect
                if (candle.symbol != symbol || candle.timeframe != timeframe ||
                    !candle.open.isFinite() || !candle.high.isFinite() ||
                    !candle.low.isFinite() || !candle.close.isFinite() ||
                    candle.low <= 0.0 || candle.high < candle.low ||
                    candle.open !in candle.low..candle.high ||
                    candle.close !in candle.low..candle.high ||
                    !candle.volume.isFinite() || candle.volume < 0.0) return@collect
                val existing = _uiState.value.candles
                val merged = (existing + candle)
                    .associateBy { it.openTime }
                    .toSortedMap()
                    .values
                    .toList()
                    .takeLast(500)
                _uiState.update { state ->
                    if (state.selectedSymbol == symbol && state.selectedTimeframe == timeframe) {
                        state.copy(candles = merged)
                    } else state
                }
                recalculateIndicators(merged, _uiState.value.indicatorSettings)
            }
        }
    }

    /**
     * Refresh genuine exchange OHLCV candles independently of bookTicker quotes.
     * Binance REST klines include actual trade volume; bid/ask events do not.
     * This is polling, not a WebSocket kline feed.
     */
    private fun startKlineRefresh(symbol: String, timeframe: Timeframe) {
        klineRefreshJob?.cancel()
        if (symbol != "BTCUSDT" && symbol != "ETHUSDT") return
        klineRefreshJob = viewModelScope.launch {
            var lastSuccessfullyRefreshedOpen = Long.MIN_VALUE
            while (isActive) {
                delay(10_000L)
                if (_uiState.value.selectedSymbol != symbol ||
                    _uiState.value.selectedTimeframe != timeframe) break
                try {
                    val now = System.currentTimeMillis()
                    val interval = timeframe.minutes * 60_000L
                    // Poll the last completed bar only. Binance also returns
                    // the forming bar when endTime is 'now', which is not a
                    // verified closed candle and can repaint the chart.
                    val lastClosedOpen = com.example.core.market.HistoricalCandleBoundary
                        .currentOpen(now, interval) - interval
                    // One successful fetch per completed candle is sufficient.
                    // Repeating the same historical request every 10 seconds
                    // wastes bandwidth and risks exchange rate limits.
                    if (lastClosedOpen == lastSuccessfullyRefreshedOpen) continue
                    val fresh = marketDataRepository.provider.getHistoricalCandles(
                        symbol, timeframe, lastClosedOpen, lastClosedOpen
                    )
                    if (fresh.isEmpty()) continue
                    // A refresh must not introduce an unfinished, mismatched or
                    // malformed exchange candle into the chart.
                    if (fresh.any { candle ->
                        candle.symbol != symbol || candle.timeframe != timeframe ||
                        candle.openTime != lastClosedOpen ||
                        !candle.open.isFinite() || !candle.high.isFinite() ||
                        !candle.low.isFinite() || !candle.close.isFinite() ||
                        candle.low <= 0.0 || candle.high < candle.low ||
                        candle.open !in candle.low..candle.high ||
                        candle.close !in candle.low..candle.high ||
                        !candle.volume.isFinite() || candle.volume < 0.0
                    }) continue
                    lastSuccessfullyRefreshedOpen = lastClosedOpen
                    if (_uiState.value.selectedSymbol != symbol ||
                        _uiState.value.selectedTimeframe != timeframe) break
                    val previous = _uiState.value.candles
                    val merged = (previous + fresh)
                        .associateBy { it.openTime }
                        .toSortedMap()
                        .values
                        .toList()
                        .takeLast(500)
                    _uiState.update { state ->
                        if (state.selectedSymbol == symbol && state.selectedTimeframe == timeframe) {
                            state.copy(candles = merged)
                        } else state
                    }
                    recalculateIndicators(merged, _uiState.value.indicatorSettings)
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    // Cancellation of the screen or symbol must stop polling promptly.
                    throw cancelled
                } catch (error: Exception) {
                    // Preserve last verified candles during temporary network failure.
                }
            }
        }
    }

    private fun recalculateIndicators(candles: List<Candle>, settings: IndicatorSettings) {
        val requestedSymbol = _uiState.value.selectedSymbol
        val requestedTimeframe = _uiState.value.selectedTimeframe
        indicatorJob?.cancel()
        indicatorJob = viewModelScope.launch(Dispatchers.Default) {
            val sma = if (settings.isSmaEnabled) TechnicalIndicators.calculateSma(candles, settings.smaPeriod) else emptyList()
            val ema = if (settings.isEmaEnabled) TechnicalIndicators.calculateEma(candles, settings.emaPeriod) else emptyList()
            val bb = if (settings.isBollingerEnabled) TechnicalIndicators.calculateBollingerBands(candles, settings.bollingerPeriod, settings.bollingerStdDev) else emptyList()
            val vwap = if (settings.isVwapEnabled) TechnicalIndicators.calculateVwap(candles) else emptyList()

            val rsi = if (settings.isRsiEnabled) TechnicalIndicators.calculateRsi(candles, settings.rsiPeriod) else emptyList()
            val macd = if (settings.isMacdEnabled) TechnicalIndicators.calculateMacd(candles, settings.macdFast, settings.macdSlow, settings.macdSignal) else emptyList()
            val atr = if (settings.isAtrEnabled) TechnicalIndicators.calculateAtr(candles, settings.atrPeriod) else emptyList()

            _uiState.update {
                // Indicator calculations run off the UI thread and can finish after
                // switching symbol/timeframe or indicator settings.
                if (it.selectedSymbol != requestedSymbol ||
                    it.selectedTimeframe != requestedTimeframe ||
                    it.indicatorSettings != settings ||
                    // Referential check avoids scanning up to 100k bars on
                    // every asynchronous indicator completion.
                    it.candles !== candles) return@update it
                it.copy(
                    smaValues = sma,
                    emaValues = ema,
                    bollingerValues = bb,
                    vwapValues = vwap,
                    rsiValues = rsi,
                    macdValues = macd,
                    atrValues = atr
                )
            }
        }
    }

    private fun subscribeToTicks(symbol: String) {
        tickJob?.cancel()
        tickJob = viewModelScope.launch {
            marketDataRepository.provider.subscribe(symbol)
            marketDataRepository.observeTicks(symbol).collect { tick ->
                if (_uiState.value.selectedSymbol != symbol) return@collect
                // A bad or mismatched quote must not overwrite the last trusted bid/ask,
                // or trigger fills and stop-loss evaluation in the trading engine.
                if (tick.symbol != symbol ||
                    tick.source !in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL") ||
                    !com.example.core.market.DataIntegrityValidator.validateTick(tick).isValid ||
                    !tick.bid.isFinite() || !tick.ask.isFinite() ||
                    tick.bid <= 0.0 || tick.ask < tick.bid ||
                    tick.timestamp <= 0L ||
                    tick.timestamp > System.currentTimeMillis() + 5_000L) return@collect
                val accepted = _uiState.value.latestTick
                if (accepted != null && tick.timestamp < accepted.timestamp) return@collect
                _uiState.update { state ->
                    if (state.selectedSymbol == symbol) {
                        // Quote events are not executed trades or OHLCV candles.
                        state.copy(latestTick = tick)
                    } else state
                }
                if (_uiState.value.selectedSymbol == symbol) {
                    tradingRepository.onTickUpdate(tick)
                }
            }
        }
    }

    private fun observeAccountPositions() {
        viewModelScope.launch {
            tradingRepository.selectedAccount.flatMapLatest { acc ->
                if (acc == null) flowOf(emptyList()) else tradingRepository.getPositionsForAccount(acc.id)
            }.collect { positions ->
                val currentSym = _uiState.value.selectedSymbol
                allPositions = positions
                val matching = positions.filter { it.symbol == currentSym }
                _uiState.update { it.copy(openPositions = matching) }
            }
        }
    }

    private fun observePendingOrders() {
        viewModelScope.launch {
            tradingRepository.selectedAccount.flatMapLatest { acc ->
                if (acc == null) flowOf(emptyList()) else tradingRepository.getPendingOrdersForAccount(acc.id)
            }.collect { orders ->
                val currentSym = _uiState.value.selectedSymbol
                allPendingOrders = orders
                val matching = orders.filter { it.symbol == currentSym }
                _uiState.update { it.copy(pendingOrders = matching) }
            }
        }
    }

    private fun observeHistoricalTrades() {
        viewModelScope.launch {
            tradingRepository.selectedAccount.flatMapLatest { acc ->
                if (acc == null) flowOf(emptyList()) else tradingRepository.getTradesForAccount(acc.id)
            }.collect { trades ->
                val currentSym = _uiState.value.selectedSymbol
                allHistoricalTrades = trades
                val matching = trades.filter { it.symbol == currentSym }
                _uiState.update { it.copy(historicalTrades = matching) }
            }
        }
    }

    private fun observeDrawings() {
        drawingJob?.cancel()
        if (drawingDao != null) {
            val sym = _uiState.value.selectedSymbol
            val tf = _uiState.value.selectedTimeframe.code
            drawingJob = viewModelScope.launch {
                drawingDao.getDrawings(sym, tf).collect { entities ->
                    val mapped = entities.mapNotNull { ChartDrawing.fromEntity(it) }
                    _uiState.update { state ->
                        if (state.selectedSymbol == sym && state.selectedTimeframe.code == tf) {
                            state.copy(drawings = mapped)
                        } else state
                    }
                }
            }
        }
    }

    private fun observeDataSourceType() {
        viewModelScope.launch {
            marketDataRepository.provider.dataSourceType.collect { ds ->
                _uiState.update { it.copy(dataSourceType = ds) }
            }
        }
    }

    fun retryCandleLoad() {
        indicatorJob?.cancel()
        candleLoadJob?.cancel()
        klineRefreshJob?.cancel()
        klineStreamJob?.cancel()
        _uiState.update {
            it.copy(
                isLoading = true,
                candleLoadError = null,
                // Retain the last verified chart history during a manual retry,
                // but clear old indicators until the new series is confirmed.
                smaValues = emptyList(), emaValues = emptyList(),
                bollingerValues = emptyList(), vwapValues = emptyList(),
                rsiValues = emptyList(), macdValues = emptyList(), atrValues = emptyList()
            )
        }
        loadCandlesForCurrentSymbol()
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }
}
