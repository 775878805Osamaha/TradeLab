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
    val selectedSymbol: String = "BTCUSDT",
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
    val message: String? = null
)

class ChartViewModel(
    private val marketDataRepository: MarketDataRepository,
    private val tradingRepository: TradingRepository,
    private val drawingDao: DrawingDao? = null
) : ViewModel() {

    private val _uiState = MutableStateFlow(ChartUiState())
    val uiState: StateFlow<ChartUiState> = _uiState.asStateFlow()

    private var tickJob: Job? = null
    private var klineRefreshJob: Job? = null
    private var drawingJob: Job? = null

    init {
        loadCandlesForCurrentSymbol()
        observeAccountPositions()
        observePendingOrders()
        observeHistoricalTrades()
        observeDataSourceType()
        observeDrawings()
    }

    fun selectSymbol(symbol: String) {
        if (_uiState.value.selectedSymbol == symbol) return
        tickJob?.cancel()
        klineRefreshJob?.cancel()
        _uiState.update { it.copy(selectedSymbol = symbol, isLoading = true, latestTick = null, candles = emptyList()) }
        loadCandlesForCurrentSymbol()
        observeDrawings()
    }

    fun selectTimeframe(timeframe: Timeframe) {
        if (_uiState.value.selectedTimeframe == timeframe) return
        tickJob?.cancel()
        klineRefreshJob?.cancel()
        _uiState.update { it.copy(selectedTimeframe = timeframe, isLoading = true, latestTick = null, candles = emptyList()) }
        loadCandlesForCurrentSymbol()
        observeDrawings()
    }

    fun updateIndicatorSettings(settings: IndicatorSettings) {
        _uiState.update { it.copy(indicatorSettings = settings) }
        recalculateIndicators(_uiState.value.candles, settings)
    }

    fun toggleCrosshair() {
        _uiState.update { it.copy(isCrosshairActive = !it.isCrosshairActive) }
    }

    fun toggleVolume() {
        _uiState.update { it.copy(isVolumeVisible = !it.isVolumeVisible) }
    }

    fun triggerResetView() {
        _uiState.update { it.copy(resetViewTrigger = System.currentTimeMillis()) }
    }

    fun setDrawingTool(tool: DrawingTool) {
        _uiState.update { it.copy(activeDrawingTool = tool) }
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
                _uiState.update { it.copy(drawings = it.drawings + drawingWithMeta) }
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
                _uiState.update { it.copy(drawings = it.drawings.filter { d -> d.id != id }) }
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
                _uiState.update { it.copy(drawings = emptyList()) }
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

    fun quickOrder(side: OrderSide, volume: Double = 0.01) {
        val state = _uiState.value
        val tick = state.latestTick
        if (tick == null || tick.symbol != state.selectedSymbol ||
            tick.source !in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL") ||
            System.currentTimeMillis() - tick.timestamp > 15_000L) {
            _uiState.update { it.copy(message = "لا يمكن تنفيذ أمر بسعر غير متصل أو قديم") }
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
                stopLoss = null,
                takeProfit = null
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

        viewModelScope.launch {
            val now = System.currentTimeMillis()
            val interval = tf.minutes * 60 * 1000L
            val from = now - (interval * 250)

            try {
                // Start live subscription even if historical REST loading fails.
                subscribeToTicks(symbol)
                val rawCandles = marketDataRepository.getCandles(symbol, tf, from, now)
                val aggregated = CandleAggregator.aggregate(rawCandles, tf)
                // Ignore responses that arrive after the user changes symbol or timeframe.
                if (_uiState.value.selectedSymbol != symbol || _uiState.value.selectedTimeframe != tf) return@launch
                _uiState.update { it.copy(candles = aggregated, isLoading = false, message = null) }
                recalculateIndicators(aggregated, _uiState.value.indicatorSettings)
                startKlineRefresh(symbol, tf)
            } catch (error: Exception) {
                if (_uiState.value.selectedSymbol == symbol && _uiState.value.selectedTimeframe == tf) {
                    _uiState.update {
                        it.copy(candles = emptyList(), isLoading = false,
                            message = "تعذر تحميل بيانات السوق: " + (error.message ?: "تحقق من الاتصال"))
                    }
                }
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
            while (isActive) {
                delay(10_000L)
                if (_uiState.value.selectedSymbol != symbol ||
                    _uiState.value.selectedTimeframe != timeframe) break
                try {
                    val now = System.currentTimeMillis()
                    val interval = timeframe.minutes * 60_000L
                    val from = (now / interval) * interval - interval
                    val fresh = marketDataRepository.provider.getHistoricalCandles(
                        symbol, timeframe, from, now
                    )
                    if (fresh.isEmpty()) continue
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
                } catch (error: Exception) {
                    // Preserve last verified candles during temporary network failure.
                }
            }
        }
    }

    private fun recalculateIndicators(candles: List<Candle>, settings: IndicatorSettings) {
        val requestedSymbol = _uiState.value.selectedSymbol
        val requestedTimeframe = _uiState.value.selectedTimeframe
        viewModelScope.launch(Dispatchers.Default) {
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
                    it.candles != candles) return@update it
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
                _uiState.update { state ->
                    // Binance bookTicker carries best bid/ask only, not executed trades,
                    // OHLC or traded volume. Never turn quote events into fabricated candles.
                    // Chart OHLCV stays sourced from Binance historical klines until a
                    // genuine Binance kline stream is implemented.
                    state.copy(latestTick = tick)
                }
                tradingRepository.onTickUpdate(tick)
            }
        }
    }

    private fun observeAccountPositions() {
        viewModelScope.launch {
            tradingRepository.selectedAccount.filterNotNull().flatMapLatest { acc ->
                tradingRepository.getPositionsForAccount(acc.id)
            }.collect { positions ->
                val currentSym = _uiState.value.selectedSymbol
                val matching = positions.filter { it.symbol == currentSym }
                _uiState.update { it.copy(openPositions = matching) }
            }
        }
    }

    private fun observePendingOrders() {
        viewModelScope.launch {
            tradingRepository.selectedAccount.filterNotNull().flatMapLatest { acc ->
                tradingRepository.getPendingOrdersForAccount(acc.id)
            }.collect { orders ->
                val currentSym = _uiState.value.selectedSymbol
                val matching = orders.filter { it.symbol == currentSym }
                _uiState.update { it.copy(pendingOrders = matching) }
            }
        }
    }

    private fun observeHistoricalTrades() {
        viewModelScope.launch {
            tradingRepository.selectedAccount.filterNotNull().flatMapLatest { acc ->
                tradingRepository.getTradesForAccount(acc.id)
            }.collect { trades ->
                val currentSym = _uiState.value.selectedSymbol
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
                    _uiState.update { it.copy(drawings = mapped) }
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

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }
}
