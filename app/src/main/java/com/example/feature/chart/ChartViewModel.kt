package com.example.feature.chart

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.indicators.*
import com.example.core.market.CandleAggregator
import com.example.core.market.MarketSymbolRegistry
import com.example.core.market.RangeBarsEngine
import com.example.core.market.RangeBarsBuildCache
import com.example.core.market.VerifiedRangeBars
import com.example.core.market.RangePriceTick
import com.example.core.market.RangeTickBatchLoader
import com.example.core.market.RangeTickSuffixCache
import com.example.core.market.RangeTickWindowContinuation
import com.example.core.market.RangeTickWindowReuse
import com.example.core.market.RangeTickHistoryTooDenseException
import com.example.core.model.*
import com.example.data.local.dao.DrawingDao
import com.example.data.repository.MarketDataRepository
import com.example.data.repository.TradingRepository
import com.example.feature.chart.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import com.example.feature.chart.history.ChartHistoryPaging
import com.example.feature.chart.history.ChartHistoryDownload
import com.example.feature.chart.history.ChartHistoryBatcher
import com.example.feature.chart.history.ChartInitialHistoryScan
import com.example.feature.chart.history.ChartHistoryRetry
import com.example.feature.chart.history.ChartHistoryRetryPolicy
import com.example.feature.chart.history.ChartClosedBarRefresh
import kotlinx.coroutines.isActive
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex

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
    val indicatorSettings: IndicatorSettings = IndicatorSettings(isEmaEnabled = false),
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
    val isDownloadingDeepHistory: Boolean = false,
    val historyDownloadMessage: String? = null,
    val historySourceWarning: String? = null,
    val candleLoadError: String? = null,
    val connectionDiagnostic: String = "لم يتم اختبار الاتصال بعد",
    val rangePrecisionDiagnostic: String? = null,
    val message: String? = null
)

class ChartViewModel(
    private val marketDataRepository: MarketDataRepository,
    private val tradingRepository: TradingRepository,
    private val drawingDao: DrawingDao? = null
) : ViewModel() {

    private val _uiState = MutableStateFlow(ChartUiState())
    val uiState: StateFlow<ChartUiState> = _uiState.asStateFlow()

    val rangeAccountGeneration: StateFlow<Long>? get() = marketDataRepository.cTrader?.accountGeneration

    private data class RangeTickWindow(val symbol: String, val source: String,
                                       val from: Long, val to: Long,
                                       val ticks: List<RangePriceTick>)
    private val rangeTickMutex = Mutex()
    private var rangeTickWindow: RangeTickWindow? = null
    private val rangeBuildCache = RangeBarsBuildCache()
    private val incompleteRangeDownload = RangeTickSuffixCache()

    /** Range history is never backed by saved OHLC or a provider fallback. */
    suspend fun loadRangeBars(symbol: String, from: Long, to: Long, sizeInPriceTicks: Int,
                              includeIncomplete: Boolean,
                              onProgress: suspend (VerifiedRangeBars) -> Unit = {},
                              onBatchProgress: suspend (Int, Int) -> Unit = { _, _ -> }): VerifiedRangeBars {
        val client = marketDataRepository.cTrader ?: error("cTrader غير متصل")
        require(symbol in com.example.core.market.VerifiedMarketQuote.forexSymbols) {
            "شموع المدى متاحة حاليًا لرموز cTrader فقط"
        }
        require(from > 0L && to >= from && to - from <= 604_800_000L)
        val source = client.sourceKey(symbol)
        val tickSize = MarketSymbolRegistry.getSymbol(symbol).tickSize
        // The broker-specific display scale is checked before downloading
        // many megabytes of ticks. Digits alone do NOT prove the minimum tick.
        val metadata = client.symbolPrecision(symbol)
        if (metadata != null && !metadata.isConfiguredTickRepresentable(tickSize)) {
            _uiState.update { it.copy(rangePrecisionDiagnostic =
                "عدم تطابق دقة الرمز: cTrader يعرض ${metadata.digits} خانات، وإعداد الحركة المحلية $tickSize غير متوافق") }
            error("دقة سعر $symbol لدى الوسيط تختلف عن إعداد TradeLab؛ يجب التحقق من Tick Size قبل حساب شموع المدى")
        }
        _uiState.update { it.copy(rangePrecisionDiagnostic = if (metadata == null)
            "دقة رمز cTrader غير متاحة: بوابة /v1/symbol-detail لم تُنشر بعد؛ حجم Tick المحلي غير مؤكد"
            else "دقة cTrader: ${metadata.digits} خانات · حجم حركة السعر المحلي قابل للتمثيل، ولم يُثبت Tick Size الفعلي") }
        // Reuse real broker quotes when Replay advances a candle or rewinds.
        // Cache never feeds a quote beyond the requested revealed cutoff.
        rangeTickMutex.lock()
        val ticks = try {
            val cached = rangeTickWindow?.takeIf {
                it.symbol == symbol && it.source == source &&
                    from <= it.to && to >= it.from
            }
            val merged = if (cached == null) {
                val partial = incompleteRangeDownload.snapshot(symbol, source, from, to)
                if (partial != null) {
                    // A previously cancelled request retained fully validated
                    // contiguous pages. Never redownload those exact BID quotes.
                    onBatchProgress(partial.ticks.size, 0)
                    if (partial.ticks.isNotEmpty()) {
                        val preview = withContext(Dispatchers.Default) {
                            RangeBarsEngine.buildVerified(symbol, partial.ticks, tickSize,
                                sizeInPriceTicks, source, includeIncomplete)
                        }
                        if (preview.candles.isNotEmpty()) onProgress(preview)
                    }
                    if (from >= partial.from) partial.ticks
                    else {
                        val older = RangeTickBatchLoader.load(from, partial.from - 1L,
                            onSliceComplete = { quotes, slices ->
                                onBatchProgress(partial.ticks.size + quotes, slices)
                            }, onVerifiedSlice = { start, end, quotes ->
                                incompleteRangeDownload.remember(symbol, source, start, end, quotes)
                            }, maxAllowedTicks = RangeTickBatchLoader.MAX_WINDOW_TICKS - partial.ticks.size) { start, end ->
                            client.historicalBidTicks(symbol, start, end)
                        }
                        ArrayList<RangePriceTick>(older.size + partial.ticks.size).apply {
                            addAll(older); addAll(partial.ticks)
                        }
                    }
                } else RangeTickBatchLoader.load(from, to,
                    onNewestSlice = { newest ->
                        if (client.sourceKey(symbol) != source)
                            error("تغير حساب cTrader أثناء جلب المدى")
                        val preview = withContext(Dispatchers.Default) {
                            RangeBarsEngine.buildVerified(symbol, newest, tickSize,
                                sizeInPriceTicks, source, includeIncomplete)
                        }
                        if (preview.candles.isNotEmpty()) onProgress(preview)
                    }, onSliceComplete = onBatchProgress,
                    onVerifiedSlice = { start, end, quotes ->
                        incompleteRangeDownload.remember(symbol, source, start, end, quotes)
                    }) { start, end ->
                    client.historicalBidTicks(symbol, start, end)
                }
            }
            else {
                // Only keep actual quotes inside the newly requested window.
                // This is a binary-search slice, not an O(n) scan of a whole
                // prior week. Otherwise excluded old quotes exhausted the
                // memory budget during Replay advances and backward pans.
                val retained = RangeTickWindowReuse.between(cached.ticks, from, to)
                val older = if (from < cached.from) {
                    val budget = RangeTickBatchLoader.MAX_WINDOW_TICKS - retained.size
                    if (budget <= 0) throw RangeTickHistoryTooDenseException(
                        "عدد بيانات Tick أكبر من ذاكرة العرض؛ استعرض فترة أقصر")
                    RangeTickWindowContinuation.downloadOlder(from, cached.from - 1L,
                        symbol, source, incompleteRangeDownload,
                        onProgress = onBatchProgress, maxQuotes = budget) { start, end ->
                        client.historicalBidTicks(symbol, start, end)
                    }
                } else emptyList()
                val newer = if (to > cached.to) {
                    val budget = RangeTickBatchLoader.MAX_WINDOW_TICKS - retained.size - older.size
                    if (budget <= 0) throw RangeTickHistoryTooDenseException(
                        "عدد بيانات Tick أكبر من ذاكرة العرض؛ استعرض فترة أقصر")
                    RangeTickBatchLoader.load(cached.to + 1L, to,
                        onSliceComplete = onBatchProgress, maxAllowedTicks = budget) { start, end ->
                        client.historicalBidTicks(symbol, start, end)
                    }
                } else emptyList()
                if (older.isEmpty() && newer.isEmpty()) retained
                else {
                    ArrayList<RangePriceTick>(older.size + retained.size + newer.size).apply {
                        addAll(older)
                        addAll(retained)
                        addAll(newer)
                    }
                }
            }
            if (client.sourceKey(symbol) != source) error("تغير حساب cTrader أثناء جلب المدى")
            // Every source path now returns the exact inclusive requested
            // interval; no filtering/copying of a second million-quote list.
            val visible = merged
            // The visible one-week window uses measured-density 1min–6h slices.
            // Keep a bounded rolling cache rather than failing after the old
            // 250k-tick ceiling during a normal backwards chart gesture.
            if (visible.size > RangeTickBatchLoader.MAX_WINDOW_TICKS)
                throw RangeTickHistoryTooDenseException(
                    "عدد بيانات Tick أكبر من ذاكرة العرض؛ استعرض فترة أقصر")
            // Retain only the requested window. Otherwise a long replay session
            // would accumulate unlimited future and past quotes in memory.
            if (rangeTickWindow?.ticks !== visible) rangeBuildCache.clear()
            rangeTickWindow = RangeTickWindow(symbol, source, from, to, visible)
            incompleteRangeDownload.clear()
            visible
        } finally { rangeTickMutex.unlock() }
        if (client.sourceKey(symbol) != source) error("تغير حساب cTrader أثناء جلب المدى")
        rangeBuildCache.find(ticks, symbol, source, tickSize,
            sizeInPriceTicks, includeIncomplete)?.let { return it }
        val computed = withContext(Dispatchers.Default) {
            RangeBarsEngine.buildVerified(symbol, ticks, tickSize,
                sizeInPriceTicks, source, includeIncomplete)
        }
        rangeTickMutex.lock()
        try {
            if (client.sourceKey(symbol) == source && rangeTickWindow?.ticks === ticks)
                rangeBuildCache.remember(ticks, symbol, source, tickSize,
                    sizeInPriceTicks, includeIncomplete, computed)
        } finally { rangeTickMutex.unlock() }
        return computed
    }

    private var candleLoadJob: Job? = null
    private var candleLoadGeneration = 0L
    private var olderHistoryJob: Job? = null
    private var historyDownloadGeneration = 0L
    private var manuallyStoppedDeepHistoryGeneration = -1L
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
        marketDataRepository.cTrader?.let { client ->
            viewModelScope.launch { client.accountGeneration.collect {
                rangeTickMutex.lock()
                try { rangeTickWindow = null; rangeBuildCache.clear()
                    incompleteRangeDownload.clear() }
                finally { rangeTickMutex.unlock() }
                _uiState.update { it.copy(rangePrecisionDiagnostic = null) }
                if (_uiState.value.selectedSymbol in com.example.core.market.VerifiedMarketQuote.forexSymbols) {
                    _uiState.update { it.copy(latestTick = null, candles = emptyList(), isLoading = true) }
                    loadCandlesForCurrentSymbol()
                }
            } }
        }
    }

    fun isVerifiedQuote(tick: Tick?, symbol: String, now: Long = System.currentTimeMillis()) =
        marketDataRepository.provider.isVerifiedQuote(tick, symbol, now)

    private fun observeConnectionDiagnostics() {
        viewModelScope.launch {
            marketDataRepository.providerDiagnostics.collect { diagnostic ->
                _uiState.update { it.copy(connectionDiagnostic = diagnostic.lastHttpDiagnostic) }
            }
        }
    }

    /** Adjust the real OHLC history depth without changing the current instrument. */
    fun setChartHistoryBars(bars: Int) {
        require(bars in setOf(100, 250, 500, 750)) { "Unsupported chart history depth" }
        if (_uiState.value.chartHistoryBars == bars) return
        _uiState.update { it.copy(chartHistoryBars = bars, isLoading = true, candleLoadError = null, olderHistoryError = null) }
        loadCandlesForCurrentSymbol()
    }

    /** Validate every backfilled candle before it can enter the visible chart. */
    private fun verifyOlderHistory(
        candles: List<Candle>,
        symbol: String,
        timeframe: Timeframe,
        start: Long,
        end: Long,
        oldest: Long
    ) {
        if (candles.any { candle ->
                candle.symbol != symbol || candle.timeframe != timeframe ||
                candle.openTime < start || candle.openTime > end ||
                candle.openTime >= oldest ||
                !candle.open.isFinite() || !candle.high.isFinite() ||
                !candle.low.isFinite() || !candle.close.isFinite() ||
                candle.low <= 0.0 || candle.high < candle.low ||
                candle.open !in candle.low..candle.high ||
                candle.close !in candle.low..candle.high ||
                !candle.volume.isFinite() || candle.volume < 0.0
            } || candles.map { it.openTime }.toSet().size != candles.size) {
            throw IllegalStateException("Invalid verified older OHLC page")
        }
    }

    /** Retries only the pending page; already merged bars never enter the retry block. */
    private suspend fun fetchOlderChartHistory(
        symbol: String, timeframe: Timeframe, oldest: Long, generation: Long
    ): List<Candle> = ChartHistoryRetry.run(onRetry = { retry ->
        _uiState.update { state ->
            if (historyDownloadGeneration != generation || state.selectedSymbol != symbol ||
                state.selectedTimeframe != timeframe || !state.isLoadingOlderHistory) state
            else state.copy(historyDownloadMessage = retry?.let {
                "انقطع الاتصال مؤقتًا؛ إعادة المحاولة ${it.attempt}/${it.maxAttempts} بعد ${it.delayMillis / 1000} ث. الشموع المحملة باقية."
            })
        }
    }) {
        ChartHistoryPaging.before(symbol, timeframe, oldest) { from, to ->
            marketDataRepository.getOlderChartCandles(symbol, timeframe, from, to)
        }
    }

    /** Load one verified timestamp page without discarding already loaded history. */
    fun loadOlderChartHistory() {
        val snapshot = _uiState.value
        if (snapshot.isLoading || snapshot.isLoadingOlderHistory || snapshot.candles.isEmpty()) return
        val symbol = snapshot.selectedSymbol
        val timeframe = snapshot.selectedTimeframe
        val oldest = snapshot.candles.first().openTime
        manuallyStoppedDeepHistoryGeneration = -1L
        val generation = ++historyDownloadGeneration
        _uiState.update { it.copy(isLoadingOlderHistory = true, olderHistoryError = null, historyDownloadMessage = null) }
        olderHistoryJob?.cancel()
        olderHistoryJob = viewModelScope.launch {
            try {
                val confirmed = fetchOlderChartHistory(symbol, timeframe, oldest, generation)
                val merged = mergeChartCandles(symbol, timeframe, confirmed, generation) ?: return@launch
                _uiState.update {
                    it.copy(isLoadingOlderHistory = false,
                        historySourceWarning = marketDataRepository.freeChartHistoryWarning(symbol) ?: it.historySourceWarning,
                        olderHistoryError = if (confirmed.isEmpty())
                        "لا تتوفر شموع أقدم من المصدر لهذه الفترة. يمكنك إعادة المحاولة." else null)
                }
                if (confirmed.isNotEmpty()) recalculateIndicators(merged, _uiState.value.indicatorSettings)
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (historyDownloadGeneration == generation &&
                    _uiState.value.selectedSymbol == symbol && _uiState.value.selectedTimeframe == timeframe) {
                    _uiState.update { it.copy(isLoadingOlderHistory = false,
                        olderHistoryError = "تعذر تحميل الأقدم: " + (error.message ?: "حاول مجددًا").take(160)) }
                }
            }
        }
    }

    /** Explicit, cancellable download. Resume uses the oldest retained verified candle. */
    fun downloadDeepChartHistory() {
        val snapshot = _uiState.value
        if (snapshot.isLoading || snapshot.isLoadingOlderHistory || snapshot.candles.isEmpty()) return
        val symbol = snapshot.selectedSymbol
        val timeframe = snapshot.selectedTimeframe
        if (snapshot.candles.size >= ChartHistoryDownload.TARGET) return
        manuallyStoppedDeepHistoryGeneration = -1L
        val generation = ++historyDownloadGeneration
        _uiState.update { it.copy(isLoadingOlderHistory = true, isDownloadingDeepHistory = true,
            olderHistoryError = null, historyDownloadMessage = null) }
        olderHistoryJob?.cancel()
        olderHistoryJob = viewModelScope.launch {
            val batcher = ChartHistoryBatcher(pageLimit = 5)
            suspend fun publishPendingHistory() {
                if (batcher.pendingPages == 0) return
                val merged = mergeChartCandles(symbol, timeframe, batcher.snapshot(), generation)
                    ?: throw kotlinx.coroutines.CancellationException("Chart changed")
                // A cancelled merge must be retryable; acknowledge the real
                // pending bars only after StateFlow accepted the whole batch.
                batcher.committed()
                recalculateIndicators(merged, _uiState.value.indicatorSettings)
                _uiState.update { it.copy(historySourceWarning =
                    marketDataRepository.freeChartHistoryWarning(symbol) ?: it.historySourceWarning) }
            }
            try {
                val result = ChartHistoryDownload.run(snapshot.candles,
                    fetchBefore = { oldest ->
                        fetchOlderChartHistory(symbol, timeframe, oldest, generation)
                    }, append = { page ->
                        batcher.stage(page)
                        if (batcher.shouldFlush) publishPendingHistory()
                    })
                // A download may end with 1–4 confirmed pages still buffered.
                publishPendingHistory()
                _uiState.update { it.copy(historyDownloadMessage = when(result) {
                    ChartHistoryDownload.Result.TARGET_REACHED -> "تم تحميل أكثر من 100 ألف شمعة فعلية"
                    ChartHistoryDownload.Result.NO_OLDER_PAGE -> "لا توجد شموع أقدم في النطاق الذي فحصه المصدر. يمكنك إعادة المحاولة."
                }) }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (historyDownloadGeneration == generation &&
                    _uiState.value.selectedSymbol == symbol && _uiState.value.selectedTimeframe == timeframe) {
                    _uiState.update { it.copy(olderHistoryError = "توقف التحميل؛ الشموع محفوظة. أعد المحاولة: " +
                        (error.message ?: "تعذر الاتصال بالمصدر").take(120)) }
                }
            } finally {
                // Even if the user explicitly stopped the download, keep real
                // pages fetched since the last UI batch. Never publish stale
                // pages into a different chart, session, or new download.
                val sameHistorySession =
                    (historyDownloadGeneration == generation ||
                        manuallyStoppedDeepHistoryGeneration == generation) &&
                    _uiState.value.selectedSymbol == symbol &&
                    _uiState.value.selectedTimeframe == timeframe
                if (sameHistorySession && batcher.pendingPages > 0) {
                    withContext(NonCancellable) {
                        try { publishPendingHistory() } catch (_: Exception) {
                            // Preserve the earlier error/cancellation cause.
                            // Already published pages remain in the chart.
                        }
                    }
                }
                if (manuallyStoppedDeepHistoryGeneration == generation)
                    manuallyStoppedDeepHistoryGeneration = -1L
                if (historyDownloadGeneration == generation &&
                    _uiState.value.selectedSymbol == symbol && _uiState.value.selectedTimeframe == timeframe &&
                    _uiState.value.isDownloadingDeepHistory) {
                    _uiState.update { it.copy(isLoadingOlderHistory = false, isDownloadingDeepHistory = false) }
                }
            }
        }
    }

    fun stopDeepChartHistory() {
        if (!_uiState.value.isDownloadingDeepHistory) return
        manuallyStoppedDeepHistoryGeneration = historyDownloadGeneration
        historyDownloadGeneration++
        olderHistoryJob?.cancel()
        _uiState.update { it.copy(isLoadingOlderHistory = false, isDownloadingDeepHistory = false,
            historyDownloadMessage = "تم إيقاف التحميل. يمكنك الاستكمال من أقدم شمعة محملة.") }
    }

    /** Merge off the UI thread; retry if a live candle arrived during the merge. */
    private suspend fun mergeChartCandles(
        symbol: String, timeframe: Timeframe, incoming: List<Candle>,
        historyGenerationGuard: Long? = null
    ): List<Candle>? {
        fun currentHistoryAccepted(): Boolean = historyGenerationGuard == null ||
            historyDownloadGeneration == historyGenerationGuard ||
            manuallyStoppedDeepHistoryGeneration == historyGenerationGuard
        while (kotlinx.coroutines.currentCoroutineContext().isActive) {
            val snapshot = _uiState.value
            if (snapshot.selectedSymbol != symbol || snapshot.selectedTimeframe != timeframe ||
                !currentHistoryAccepted()) return null
            val merged = withContext(Dispatchers.Default) { ChartHistoryPaging.merge(snapshot.candles, incoming) }
            var applied = false
            _uiState.update { state ->
                applied = state.selectedSymbol == symbol && state.selectedTimeframe == timeframe &&
                    state.candles === snapshot.candles && currentHistoryAccepted()
                if (applied) state.copy(candles = merged) else state
            }
            if (applied) return merged
        }
        return null
    }

    fun retryChartHistory() {
        _uiState.update { it.copy(isLoading = true, candleLoadError = null) }
        loadCandlesForCurrentSymbol()
    }


    fun selectSymbol(symbol: String) {
        if (_uiState.value.selectedSymbol == symbol) return
        manuallyStoppedDeepHistoryGeneration = -1L
        // Prevent unsupported instruments from retaining a previous exchange quote.
        // The history loader will show an explicit unavailable-source message.
        candleLoadJob?.cancel()
        olderHistoryJob?.cancel()
        tickJob?.cancel()
        klineRefreshJob?.cancel()
        klineStreamJob?.cancel()
        indicatorJob?.cancel()
        _uiState.update {
            it.copy(
                selectedSymbol = symbol, isLoading = true, candleLoadError = null,
                isLoadingOlderHistory = false, isDownloadingDeepHistory = false, historyDownloadMessage = null, historySourceWarning = null, olderHistoryError = null,
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
        manuallyStoppedDeepHistoryGeneration = -1L
        // Keep the existing bid/ask subscription: a timeframe change does not
        // change the instrument and should not disconnect its live quote.
        klineRefreshJob?.cancel()
        klineStreamJob?.cancel()
        olderHistoryJob?.cancel()
        indicatorJob?.cancel()
        _uiState.update {
            it.copy(
                selectedTimeframe = timeframe, isLoading = true, candleLoadError = null,
                isLoadingOlderHistory = false, isDownloadingDeepHistory = false, historyDownloadMessage = null, historySourceWarning = null, olderHistoryError = null,
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
        _uiState.update {
            if(it.indicatorSettings==settings) it else it.copy(indicatorSettings=settings,
                smaValues=emptyList(),emaValues=emptyList(),bollingerValues=emptyList(),
                vwapValues=emptyList(),rsiValues=emptyList(),macdValues=emptyList(),atrValues=emptyList())
        }
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

    fun addDrawing(drawing: ChartDrawing, onCreated: (Long) -> Unit = {}) {
        val sym = _uiState.value.selectedSymbol
        val tf = _uiState.value.selectedTimeframe.code
        val drawingWithMeta = drawing.copy(symbol = sym, timeframe = tf)

        viewModelScope.launch {
            if (drawingDao != null) {
                val insertedId = withContext(Dispatchers.IO) {
                    drawingDao.insertDrawing(drawingWithMeta.toEntity())
                }
                if (insertedId > 0L && _uiState.value.selectedSymbol == sym &&
                    _uiState.value.selectedTimeframe.code == tf) onCreated(insertedId)
            } else {
                var createdId: Long? = null
                _uiState.update { state ->
                    if (state.selectedSymbol == sym && state.selectedTimeframe.code == tf) {
                        val nextId = (state.drawings.maxOfOrNull { it.id } ?: 0L) + 1L
                        createdId = nextId
                        state.copy(drawings = state.drawings + drawingWithMeta.copy(id = nextId))
                    } else state
                }
                createdId?.let(onCreated)
            }
        }
        _uiState.update { it.copy(activeDrawingTool = DrawingTool.NONE) }
    }

    fun updateDrawing(drawing: ChartDrawing) {
        if (drawing.symbol != _uiState.value.selectedSymbol || drawing.timeframe != _uiState.value.selectedTimeframe.code) return
        viewModelScope.launch {
            if (drawingDao != null) withContext(Dispatchers.IO) { drawingDao.insertDrawing(drawing.toEntity()) }
            else _uiState.update { state -> state.copy(drawings = state.drawings.map { if (it.id == drawing.id) drawing else it }) }
        }
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

    fun closeChartPosition(positionId: Long, partialVolume: Double? = null) {
        val state = _uiState.value
        val position = state.openPositions.firstOrNull { it.id == positionId } ?: return
        val tick = state.latestTick
        if (tick == null || !isVerifiedQuote(tick, position.symbol, System.currentTimeMillis())) {
            _uiState.update { it.copy(message = "يلزم سعر حديث وموثوق لإغلاق الصفقة") }
            return
        }
        if (partialVolume != null && !com.example.feature.chart.validPartialClose(position.symbol, position.volume, partialVolume)) {
            _uiState.update { it.copy(message = "حجم الإغلاق الجزئي غير صالح") }
            return
        }
        val exitPrice = if (position.side == PositionSide.BUY) tick.bid else tick.ask
        viewModelScope.launch {
            runCatching { tradingRepository.closePosition(positionId, exitPrice, ExitReason.MANUAL_CLOSE, partialVolume).getOrThrow() }
                .onSuccess { _uiState.update { it.copy(message = "تم إغلاق الحجم المطلوب من الصفقة") } }
                .onFailure { error -> _uiState.update { it.copy(message = error.message ?: "فشل إغلاق الصفقة") } }
        }
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
        if (tick == null || !isVerifiedQuote(tick, state.selectedSymbol)) {
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
        manuallyStoppedDeepHistoryGeneration = -1L
        historyDownloadGeneration++
        val candleGeneration = ++candleLoadGeneration
        olderHistoryJob?.cancel()
        _uiState.update { it.copy(isLoadingOlderHistory = false, isDownloadingDeepHistory = false, historyDownloadMessage = null, historySourceWarning = null, olderHistoryError = null) }
        val symbol = _uiState.value.selectedSymbol
        val tf = _uiState.value.selectedTimeframe
        val requestedBars = _uiState.value.chartHistoryBars

        candleLoadJob?.cancel()
        candleLoadJob = viewModelScope.launch {
            if (candleLoadGeneration != candleGeneration) return@launch
            if (!marketDataRepository.supportsHistoricalSymbol(symbol)) {
                if (candleLoadGeneration == candleGeneration &&
                    _uiState.value.selectedSymbol == symbol && _uiState.value.selectedTimeframe == tf) {
                    _uiState.update {
                        it.copy(candles = emptyList(), latestTick = null, isLoading = false,
                            candleLoadError = "لا يوجد مصدر تاريخي مدعوم لهذا الرمز.")
                    }
                }
                return@launch
            }
            val now = System.currentTimeMillis()
            val interval = tf.minutes * 60_000L
            // Binance follows UTC exchange opens; cTrader uses real broker
            // open-tick timestamps, which may shift on H4/D1/W1. A source-aware
            // upper bound prevents omitting the latest completed broker bar.
            val lastClosedOpen = com.example.core.market.HistoricalCandleBoundary
                .latestClosedRequestTo(now, interval,
                    symbol in com.example.core.market.VerifiedMarketQuote.forexSymbols)
            try {
                // Start live subscription even if historical REST loading fails.
                if (com.example.core.market.VerifiedMarketQuote.supports(symbol) &&
                    candleLoadGeneration == candleGeneration) subscribeToTicks(symbol)
                // A provider may have fewer verified bars than the requested history.
                // Retry smaller, recent windows instead of replacing the entire chart
                // with an error. Never fabricate missing OHLC data.
                var rawCandles = emptyList<com.example.core.model.Candle>()
                var lastHistoryError: Exception? = null
                // Gold/FX markets close over weekends and sometimes holidays.
                // Scan contiguous, bounded windows; no gap can be skipped just
                // because a broker's next real open is shifted by some minutes.
                val initialDepths = listOf(requestedBars, 100, 40, 10, 1)
                    .distinct().filter { it in 1..requestedBars }
                val scanPlan = ChartInitialHistoryScan.windows(
                    lastClosedOpen = lastClosedOpen, intervalMillis = interval,
                    initialBars = requestedBars,
                    brokerTimed = symbol in com.example.core.market.VerifiedMarketQuote.forexSymbols
                )
                for (window in scanPlan) {
                    if (candleLoadGeneration != candleGeneration) return@launch
                    val depths = if (window.isInitial) initialDepths else
                        listOf(window.bars, 100, 40, 10, 1).distinct()
                    for (depth in depths) {
                        val attemptFrom = (window.to - interval * (depth - 1L))
                            .coerceAtLeast(window.from)
                        try {
                            val fetched = marketDataRepository.getCandles(
                                symbol, tf, attemptFrom, window.to
                            )
                            if (fetched.isNotEmpty()) {
                                // Never accept a page from a different symbol,
                                // timeframe, or requested window.
                                verifyOlderHistory(
                                    fetched, symbol, tf, attemptFrom, window.to,
                                    lastClosedOpen + interval
                                )
                                // Wider closed-session queries should not
                                // silently override the selected chart depth.
                                rawCandles = fetched.takeLast(requestedBars)
                                break
                            }
                            if (!window.isInitial && depth == window.bars) break
                        } catch (cancelled: kotlinx.coroutines.CancellationException) {
                            throw cancelled
                        } catch (error: Exception) {
                            // Only a verified empty broker response warrants
                            // looking in prior closed sessions. Authentication,
                            // network and OHLC-integrity errors must fail fast.
                            if (!ChartHistoryRetryPolicy.shouldSearchOlderSession(error)) throw error
                            lastHistoryError = error
                            if (!window.isInitial && depth == window.bars) break
                        }
                    }
                    if (rawCandles.isNotEmpty()) break
                }
                if (rawCandles.isEmpty() && lastHistoryError != null) throw lastHistoryError
                // The repository already returns verified TARGET-timeframe bars.
                // Re-bucketing W1 here shifts Monday opens to Unix-epoch Thursday.
                val aggregated = rawCandles
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
                if (candleLoadGeneration != candleGeneration ||
                    _uiState.value.selectedSymbol != symbol || _uiState.value.selectedTimeframe != tf ||
                    _uiState.value.chartHistoryBars != requestedBars) return@launch
                _uiState.update { it.copy(candles = aggregated, isLoading = false, candleLoadError = if (aggregated.isEmpty()) "لا تتوفر شموع مؤكدة لهذا الرمز والفاصل الزمني. حاول مجددًا." else null, message = null) }
                recalculateIndicators(aggregated, _uiState.value.indicatorSettings)
                if (symbol in setOf("BTCUSDT", "ETHUSDT")) {
                    startKlineRefresh(symbol, tf)
                    startKlineStream(symbol, tf)
                } else {
                    // Forex uses its broker quote subscription; never request
                    // Binance crypto klines for a forex/metal symbol.
                    startKlineRefresh(symbol, tf)
                    klineStreamJob?.cancel()
                }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (candleLoadGeneration == candleGeneration &&
                    _uiState.value.selectedSymbol == symbol && _uiState.value.selectedTimeframe == tf) {
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
                val merged = mergeChartCandles(symbol, timeframe, listOf(candle)) ?: return@collect
                recalculateIndicators(merged, _uiState.value.indicatorSettings)
            }
        }
    }

    /**
     * Poll completed, source-verified OHLCV bars independently of bid/ask quotes.
     * Binance uses exact UTC candle-open boundaries; cTrader bars can open on
     * the broker's first tick, so use a narrow historical window instead.
     */
    private fun startKlineRefresh(symbol: String, timeframe: Timeframe) {
        klineRefreshJob?.cancel()
        if (!com.example.core.market.VerifiedMarketQuote.supports(symbol)) return
        klineRefreshJob = viewModelScope.launch {
            val brokerTimed = symbol !in setOf("BTCUSDT", "ETHUSDT")
            var lastSuccessfullyRefreshedOpen = _uiState.value.candles.lastOrNull()?.openTime ?: Long.MIN_VALUE
            var lastAttemptKey = Long.MIN_VALUE
            var attemptsForKey = 0
            while (isActive) {
                delay(10_000L)
                if (_uiState.value.selectedSymbol != symbol ||
                    _uiState.value.selectedTimeframe != timeframe) break
                try {
                    val now = System.currentTimeMillis()
                    val window = ChartClosedBarRefresh.window(now, timeframe, brokerTimed)
                    // Fixed-grid Binance has exactly one last completed open;
                    // broker opens are not required to be UTC-grid aligned.
                    if (!brokerTimed && window.to == lastSuccessfullyRefreshedOpen) continue
                    if (window.attemptKey != lastAttemptKey) {
                        lastAttemptKey = window.attemptKey
                        attemptsForKey = 0
                    }
                    // Closed broker sessions and outages cannot trigger an
                    // unbounded request every ten seconds.
                    if (attemptsForKey >= 3) continue
                    attemptsForKey++
                    val fetched = if (!brokerTimed) {
                        marketDataRepository.provider.getHistoricalCandles(symbol, timeframe, window.from, window.to)
                    } else {
                        marketDataRepository.getCandles(symbol, timeframe, window.from, window.to)
                    }
                    if (fetched.isEmpty()) continue
                    // The only acceptable update is a closed, valid bar from
                    // the selected instrument, timeframe and verified provider.
                    if (fetched.any { candle ->
                        candle.symbol != symbol || candle.timeframe != timeframe ||
                        candle.openTime !in window.from..window.to ||
                        (!brokerTimed && candle.openTime != window.to) ||
                        !candle.open.isFinite() || !candle.high.isFinite() ||
                        !candle.low.isFinite() || !candle.close.isFinite() ||
                        candle.low <= 0.0 || candle.high < candle.low ||
                        candle.open !in candle.low..candle.high ||
                        candle.close !in candle.low..candle.high ||
                        !candle.volume.isFinite() || candle.volume < 0.0
                    }) continue
                    // Do not repaint historical candles or repeatedly merge
                    // the same cTrader bars when the broker market is closed.
                    val fresh = if (brokerTimed) fetched.filter {
                        it.openTime > lastSuccessfullyRefreshedOpen
                    } else fetched
                    if (fresh.isEmpty()) continue
                    if (_uiState.value.selectedSymbol != symbol ||
                        _uiState.value.selectedTimeframe != timeframe) break
                    val merged = mergeChartCandles(symbol, timeframe, fresh) ?: break
                    lastSuccessfullyRefreshedOpen = fresh.maxOf { it.openTime }
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
            val calculated = ChartIndicatorPreparation.calculate(candles, settings)

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
                    smaValues = calculated.sma,
                    emaValues = calculated.ema,
                    bollingerValues = calculated.bollinger,
                    vwapValues = calculated.vwap,
                    rsiValues = calculated.rsi,
                    macdValues = calculated.macd,
                    atrValues = calculated.atr
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
                if (!isVerifiedQuote(tick, symbol)) return@collect
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
