package com.example.feature.replay

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.execution.ExecutionEngine
import com.example.core.execution.PositionEvaluation
import com.example.core.model.*
import com.example.core.replay.HistoricalReplayEngine
import com.example.core.replay.ReplayAccountMath
import com.example.core.replay.ReplayDataView
import com.example.core.strategy.SignalAction
import com.example.core.strategy.Strategy
import com.example.core.strategy.StrategyContext
import com.example.data.repository.MarketDataRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

enum class ReplayInteractionMode {
    MANUAL,
    STRATEGY
}

data class ReplayUiState(
    val symbol: String = "BTCUSDT",
    val timeframe: Timeframe = Timeframe.M15,
    val initialBalance: Double = 50.0,
    val maxOpenPositions: Int = 10,
    val maxPendingOrders: Int = 20,
    val maxDrawdownPercent: Double = 100.0,
    val peakEquity: Double = 50.0,
    val maxObservedDrawdownPercent: Double = 0.0,
    val equitySamples: List<ReplayEquitySample> = emptyList(),
    val riskGuardEnabled: Boolean = true,
    val maxConsecutiveLosses: Int = 0,
    val maxSessionLossUsd: Double = 0.0,
    val currentBalance: Double = 50.0,
    val currentEquity: Double = 50.0,
    val visibleCandles: List<Candle> = emptyList(),
    val currentCandle: Candle? = null,
    val latestTick: Tick? = null,
    val openPositions: List<Position> = emptyList(),
    val pendingOrders: List<Order> = emptyList(),
    val closedTrades: List<TradeJournalEntry> = emptyList(),
    val isPlaying: Boolean = false,
    val isBatchAdvancing: Boolean = false,
    val batchCompletedBars: Int = 0,
    val batchRequestedBars: Int = 0,
    val speed: Float = 1.0f,
    val currentIndex: Int = 0,
    val totalCandles: Int = 0,
    val requestedHistoryBars: Int = 300,
    val historyEndOffsetBars: Int = 0,
    val currentReplayTime: Long = 0L,
    val interactionMode: ReplayInteractionMode = ReplayInteractionMode.MANUAL,
    val selectedStrategyName: String? = null,
    val lastSignalMessage: String? = null,
    val isLoading: Boolean = false,
    val message: String? = null
)

data class ReplayEquitySample(val candleIndex: Int, val equity: Double, val balance: Double)

class ReplayViewModel(
    private val marketDataRepository: MarketDataRepository,
    private val executionEngine: ExecutionEngine = ExecutionEngine(),
    val replayEngine: HistoricalReplayEngine = HistoricalReplayEngine()
) : ViewModel() {

    private val _uiState = MutableStateFlow(ReplayUiState(isLoading = true))
    val uiState: StateFlow<ReplayUiState> = _uiState.asStateFlow()

    private val openPositions = mutableListOf<Position>()
    private val pendingOrders = mutableListOf<Order>()
    private val closedTrades = mutableListOf<TradeJournalEntry>()
    private var nextId = 1L
    private var replayLoadJob: Job? = null
    private var batchAdvanceJob: Job? = null
    private var batchAdvanceGeneration: Long = 0L
    private fun cancelBatchAdvance() {
        batchAdvanceGeneration++
        batchAdvanceJob?.cancel()
        batchAdvanceJob = null
        _uiState.update {
            if (!it.isBatchAdvancing && it.batchCompletedBars == 0) it
            else it.copy(isBatchAdvancing = false, batchCompletedBars = 0, batchRequestedBars = 0)
        }
    }

    private data class AccountSnapshot(
        val balance: Double,
        val equity: Double,
        val positions: List<Position>,
        val orders: List<Order>,
        val trades: List<TradeJournalEntry>,
        val nextOrderId: Long,
        val peakEquity: Double,
        val maxObservedDrawdownPercent: Double,
        val equitySamples: List<ReplayEquitySample>
    )
    private val accountSnapshots = java.util.TreeMap<Int, AccountSnapshot>()

    private fun saveAccountSnapshot() {
        val index = replayEngine.currentIndex.value
        // Any new execution or account edit forks the timeline at this bar.
        // Checkpoints from a previous future must never be restored.
        accountSnapshots.tailMap(index, false).clear()
        replayEngine.discardCheckpointsAfter(index)
        accountSnapshots[index] = AccountSnapshot(
            balance = _uiState.value.currentBalance,
            equity = _uiState.value.currentEquity,
            positions = openPositions.toList(),
            orders = pendingOrders.toList(),
            trades = closedTrades.toList(),
            nextOrderId = nextId,
            peakEquity = _uiState.value.peakEquity,
            maxObservedDrawdownPercent = _uiState.value.maxObservedDrawdownPercent,
            equitySamples = _uiState.value.equitySamples
        )
    }

    private fun restoreAccountSnapshot(snapshot: AccountSnapshot) {
        openPositions.clear()
        openPositions.addAll(snapshot.positions)
        pendingOrders.clear()
        pendingOrders.addAll(snapshot.orders)
        closedTrades.clear()
        closedTrades.addAll(snapshot.trades)
        nextId = snapshot.nextOrderId
        _uiState.update {
            it.copy(
                currentBalance = snapshot.balance,
                currentEquity = snapshot.equity,
                openPositions = openPositions.toList(),
                pendingOrders = pendingOrders.toList(),
                closedTrades = closedTrades.toList(),
                peakEquity = snapshot.peakEquity,
                maxObservedDrawdownPercent = snapshot.maxObservedDrawdownPercent,
                equitySamples = snapshot.equitySamples
            )
        }
    }

    private var activeStrategy: Strategy? = null

    fun setStrategy(strategy: Strategy?) {
        cancelBatchAdvance()
        replayEngine.pause()
        activeStrategy = strategy
        _uiState.update { it.copy(selectedStrategyName = strategy?.name) }
    }

    init {
        setupReplayEngineCallbacks()
        loadReplayData()
    }

    private fun setupReplayEngineCallbacks() {
        replayEngine.onCandleRevealed = { candle, tick, dataView ->
            evaluateOnReplayCandle(candle, tick, dataView)
        }

        viewModelScope.launch {
            replayEngine.visibleCandles.collect { list ->
                _uiState.update { it.copy(visibleCandles = list) }
            }
        }
        viewModelScope.launch {
            replayEngine.currentCandle.collect { candle ->
                _uiState.update { it.copy(currentCandle = candle) }
            }
        }
        viewModelScope.launch {
            replayEngine.currentTick.collect { tick ->
                _uiState.update { it.copy(latestTick = tick) }
            }
        }
        viewModelScope.launch {
            replayEngine.isPlaying.collect { playing ->
                _uiState.update { it.copy(isPlaying = playing) }
            }
        }
        viewModelScope.launch {
            replayEngine.speed.collect { sp ->
                _uiState.update { it.copy(speed = sp) }
            }
        }
        viewModelScope.launch {
            replayEngine.currentIndex.collect { idx ->
                _uiState.update { it.copy(currentIndex = idx) }
            }
        }
        viewModelScope.launch {
            replayEngine.totalCandles.collect { total ->
                _uiState.update { it.copy(totalCandles = total) }
            }
        }
        viewModelScope.launch {
            replayEngine.currentReplayTime.collect { time ->
                _uiState.update { it.copy(currentReplayTime = time) }
            }
        }
    }

    /**
     * Load externally exported broker OHLCV history without inventing prices.
     * User-provided data is labeled USER_IMPORTED and never passed off as
     * authenticated provider history. A new dataset clears the old account.
     */
    fun loadImportedCsv(csv: String, symbol: String, timeframe: Timeframe, provenance: String) {
        if (csv.length > 12_000_000) {
            _uiState.update { it.copy(message = "ملف CSV كبير جدًا؛ الحد الأقصى 12 ميجابايت") }
            return
        }
        cancelBatchAdvance()
        replayLoadJob?.cancel()
        replayEngine.pause()
        replayEngine.clear()
        resetReplayAccount()
        nextId = 1L
        accountSnapshots.clear()
        _uiState.update {
            it.copy(symbol = symbol, timeframe = timeframe, isLoading = true,
                message = null, visibleCandles = emptyList(), currentCandle = null,
                latestTick = null, currentIndex = 0, totalCandles = 0,
                currentReplayTime = 0L, isPlaying = false)
        }
        replayLoadJob = viewModelScope.launch {
            try {
                val candles = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                    com.example.core.market.HistoricalCsvImporter.parse(
                        csv, symbol, timeframe, provenance, maxBars = 20_000
                    )
                }
                if (candles.size < 50) {
                    _uiState.update { it.copy(isLoading = false, message = "يلزم 50 شمعة على الأقل لاختبار Replay") }
                    return@launch
                }
                replayEngine.initialize(candles, startIndex = minOf(20, candles.lastIndex))
                _uiState.update { it.copy(isLoading = false, message = "تم استيراد ${candles.size} شمعة من $provenance (بيانات خارجية)") }
                saveAccountSnapshot()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _uiState.update { it.copy(isLoading = false, message = "فشل استيراد CSV: تحقق من الأعمدة والشموع وترتيب الوقت والمصدر") }
            }
        }
    }

    fun configureHistoricalApiKey(key: String) {
        marketDataRepository.configureTwelveDataKey(key)
        _uiState.update { it.copy(message = if (key.isBlank()) "تم إلغاء مفتاح Twelve Data" else "تم ضبط مفتاح Twelve Data في الذاكرة لهذه الجلسة") }
    }

    fun hasHistoricalApiKey(): Boolean = marketDataRepository.hasTwelveDataKey()

    fun loadReplayData(
        symbol: String = "BTCUSDT",
        tf: Timeframe = Timeframe.M15,
        historyBars: Int = _uiState.value.requestedHistoryBars,
        endOffsetBars: Int = _uiState.value.historyEndOffsetBars
    ) {
        require(endOffsetBars in 0..100_000) { "Historical offset must be 0 to 100000 bars" }
        require(historyBars in 50..5_000) { "Replay history must contain 50 to 5000 bars" }
        cancelBatchAdvance()
        replayLoadJob?.cancel()
        replayEngine.pause()
        // Immediately invalidate the previous engine quote as well as UI flows:
        // executeOrder reads the engine directly and must never trade old data.
        replayEngine.clear()
        // A new dataset must never inherit positions, pending orders, journal or IDs
        // from the previous replay session, even if loading subsequently fails.
        resetReplayAccount()
        nextId = 1L
        accountSnapshots.clear()
        // Do not continue displaying a previous instrument's replay while switching.
        _uiState.update {
            it.copy(
                symbol = symbol, timeframe = tf, requestedHistoryBars = historyBars,
                historyEndOffsetBars = endOffsetBars,
                isLoading = true, message = null,
                visibleCandles = emptyList(), currentCandle = null, latestTick = null,
                currentIndex = 0, totalCandles = 0, currentReplayTime = 0L,
                isPlaying = false
            )
        }
        if (!marketDataRepository.supportsHistoricalSymbol(symbol)) {
            _uiState.update {
                it.copy(isLoading = false, message = "لا يوجد مزود بيانات تاريخية معتمد لهذا الرمز.")
            }
            return
        }
        // Gold and forex use the verified keyless historical provider.
        replayLoadJob = viewModelScope.launch {
            try {
                val now = System.currentTimeMillis()
                val interval = tf.minutes * 60_000L
                // Historical data requires aligned, fully closed candle OPEN timestamps.
                // Requesting an unfinished bar causes the verified repository to reject replay.
                val latestClosedOpen = com.example.core.market.HistoricalCandleBoundary
                    .currentOpen(now, interval) - interval
                val lastClosedOpen = latestClosedOpen - interval * endOffsetBars.toLong()
                require(lastClosedOpen >= interval * (historyBars - 1L)) {
                    "Historical range predates available exchange timestamps"
                }
                val from = lastClosedOpen - interval * (historyBars - 1L)
                val candles = marketDataRepository.getCandles(symbol, tf, from, lastClosedOpen)
                if (candles.size < 2) {
                    _uiState.update {
                        it.copy(isLoading = false, message = "لا توجد شموع تاريخية موثوقة لهذا الرمز في النطاق المطلوب.")
                    }
                    return@launch
                }
                // A superseded request must not initialize the engine with the old instrument.
                if (_uiState.value.symbol != symbol ||
                    _uiState.value.timeframe != tf ||
                    _uiState.value.requestedHistoryBars != historyBars ||
                    _uiState.value.historyEndOffsetBars != endOffsetBars) return@launch
                val audit = com.example.core.market.HistoricalDataAudit.inspect(candles)
                val validation = com.example.core.market.DataIntegrityValidator
                    .validateHistoricalSeries(candles)
                if (!audit.safeForBacktest || !validation.isValid || candles.first().symbol != symbol ||
                    candles.first().timeframe != tf ||
                    candles.first().openTime < from ||
                    candles.last().openTime > lastClosedOpen) {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            message = "بيانات Replay غير متسقة؛ أُلغيت الجلسة لحماية نتائج الاختبار"
                        )
                    }
                    return@launch
                }
                replayEngine.initialize(candles, startIndex = minOf(20, candles.lastIndex))
                _uiState.update { it.copy(isLoading = false) }
                saveAccountSnapshot()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                // A failed, cancelled or replaced load must never overwrite another session.
                _uiState.update { state ->
                    if (state.symbol == symbol && state.timeframe == tf &&
                        state.requestedHistoryBars == historyBars &&
                        state.historyEndOffsetBars == endOffsetBars) {
                        state.copy(
                            isLoading = false,
                            message = "تعذر تحميل بيانات إعادة العرض لهذا الرمز. تحقق من الاتصال وتوفر الشموع المكتملة."
                        )
                    } else state
                }
            }
        }
    }

    fun play() {
        cancelBatchAdvance()
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) {
            _uiState.update { it.copy(message = "انتظر اكتمال تحميل بيانات Replay أولًا") }
            return
        }
        if (replayEngine.currentIndex.value >= _uiState.value.totalCandles - 1) {
            _uiState.update { it.copy(message = "انتهت الشموع التاريخية؛ أعد الجلسة أو حمّل فترة أخرى") }
            return
        }
        replayEngine.play()
    }
    fun pause() {
        cancelBatchAdvance()
        replayEngine.pause()
    }
    fun stepForward() {
        cancelBatchAdvance()
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) {
            _uiState.update { it.copy(message = "لا توجد شموع Replay جاهزة للتقدم") }
            return
        }
        if (!replayEngine.stepForward()) {
            _uiState.update { it.copy(message = "لا توجد شموع إضافية للتقدم") }
        }
    }

    fun advanceBars(count: Int) {
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) {
            _uiState.update { it.copy(message = "لا توجد شموع Replay جاهزة للتقدم") }
            return
        }
        if (_uiState.value.currentIndex >= _uiState.value.totalCandles - 1) {
            _uiState.update { it.copy(message = "وصلت إلى آخر شمعة في جلسة الإعادة") }
            return
        }
        if (count !in 1..500) {
            _uiState.update { it.copy(message = "عدد الشموع يجب أن يكون بين 1 و500") }
            return
        }
        cancelBatchAdvance()
        replayEngine.pause()
        // Execute every candle in order; cancellation invalidates this generation.
        // A bounded yield allows UI commands to interrupt a long session.
        val generation = batchAdvanceGeneration
        _uiState.update { it.copy(isBatchAdvancing = true, batchCompletedBars = 0, batchRequestedBars = count) }
        batchAdvanceJob = viewModelScope.launch {
            var advanced = 0
            try {
                while (advanced < count &&
                    generation == batchAdvanceGeneration &&
                    kotlinx.coroutines.currentCoroutineContext()[Job]?.isActive == true &&
                    replayEngine.stepForward()) {
                    advanced++
                    if (advanced % 5 == 0) {
                        _uiState.update { it.copy(batchCompletedBars = advanced) }
                        kotlinx.coroutines.yield()
                    }
                }
                if (generation == batchAdvanceGeneration) {
                    _uiState.update {
                        it.copy(
                            batchCompletedBars = advanced,
                            message = "تم تنفيذ $advanced شمعة بالتسلسل دون تخطي أحداث التداول"
                        )
                    }
                }
            } finally {
                if (generation == batchAdvanceGeneration) {
                    batchAdvanceJob = null
                                _uiState.update { it.copy(isBatchAdvancing = false, batchCompletedBars = advanced) }
                }
            }
        }
    }

    fun stepBackward() {
        cancelBatchAdvance()
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) {
            _uiState.update { it.copy(message = "لا توجد جلسة Replay جاهزة للرجوع") }
            return
        }
        replayEngine.pause()
        val targetIndex = replayEngine.currentIndex.value - 1
        if (targetIndex < 0) {
            _uiState.update { it.copy(message = "وصلت إلى بداية بيانات Replay") }
            return
        }
        val snapshot = accountSnapshots[targetIndex]
        val hasTradingHistory = openPositions.isNotEmpty() ||
            pendingOrders.isNotEmpty() || closedTrades.isNotEmpty() ||
            accountSnapshots.values.any { it.positions.isNotEmpty() || it.orders.isNotEmpty() || it.trades.isNotEmpty() }
        if (snapshot == null && hasTradingHistory) {
            _uiState.update { it.copy(message = "لا تتوفر نقطة استعادة مالية لهذه الشمعة") }
            return
        }
        if (replayEngine.stepBackward()) {
            if (snapshot != null) restoreAccountSnapshot(snapshot)
            else saveAccountSnapshot() // A no-trade timeline can safely navigate freely.
            // Future checkpoints belong to an abandoned timeline.
            accountSnapshots.tailMap(targetIndex, false).clear()
            // Invalidate the engine's separate checkpoint cache too.
            replayEngine.discardCheckpointsAfter(targetIndex)
            _uiState.update { it.copy(message = "تمت استعادة حالة الحساب عند الشمعة #$targetIndex") }
        }
    }

    fun jumpToTimestamp(timestamp: Long) {
        cancelBatchAdvance()
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) {
            _uiState.update { it.copy(message = "لا يمكن الانتقال قبل تحميل بيانات Replay") }
            return
        }
        // Arbitrary jumps can skip execution of stops and strategies.
        // Keep jumps disabled after trades until timeline replay is transactional.
        if (openPositions.isNotEmpty() || pendingOrders.isNotEmpty() || closedTrades.isNotEmpty() ||
            accountSnapshots.values.any { it.positions.isNotEmpty() || it.orders.isNotEmpty() || it.trades.isNotEmpty() }) {
            _uiState.update { it.copy(message = "القفز بعد التداول غير متاح؛ استخدم الرجوع شمعة واحدة") }
            return
        }
        replayEngine.pause()
        // Seeking on a pristine account starts a fresh, non-trading timeline.
        // Discard old checkpoint history so it cannot be restored accidentally.
        accountSnapshots.clear()
        replayEngine.jumpToTimestamp(timestamp)
        saveAccountSnapshot()
    }

    fun setSpeed(sp: Float) {
        cancelBatchAdvance()
        if (!sp.isFinite() || sp <= 0f) {
            _uiState.update { it.copy(message = "سرعة Replay يجب أن تكون موجبة وصالحة") }
            return
        }
        replayEngine.setSpeed(sp)
    }

    fun configureExtendedRiskLimits(
        enabled: Boolean,
        maxLosses: Int,
        maxLossUsd: Double
    ) {
        cancelBatchAdvance()
        if (maxLosses !in 0..100 || !maxLossUsd.isFinite() || maxLossUsd < 0.0) {
            _uiState.update { it.copy(message = "إعدادات حدود الخسائر غير صالحة") }
            return
        }
        replayEngine.pause()
        _uiState.update {
            it.copy(
                riskGuardEnabled = enabled,
                maxConsecutiveLosses = maxLosses,
                maxSessionLossUsd = maxLossUsd,
                message = "تم تحديث حماية الخسائر لجلسة Replay"
            )
        }
    }

    private fun consecutiveLosses(): Int {
        // Avoid allocating a complete P&L list on every pending fill and
        // market order. Only the trailing run of losses is relevant.
        var losses = 0
        for (index in closedTrades.lastIndex downTo 0) {
            val pnl = closedTrades[index].netProfitLoss
            if (!pnl.isFinite() || pnl >= 0.0) break
            losses++
        }
        return losses
    }

    fun configureRiskLimits(maxPositions: Int, maxOrders: Int, maxDrawdown: Double) {
        cancelBatchAdvance()
        if (maxPositions !in 1..100 || maxOrders !in 1..200 ||
            !maxDrawdown.isFinite() || maxDrawdown !in 1.0..100.0) {
            _uiState.update { it.copy(message = "إعدادات المخاطر غير صالحة") }
            return
        }
        replayEngine.pause()
        _uiState.update {
            it.copy(
                maxOpenPositions = maxPositions,
                maxPendingOrders = maxOrders,
                maxDrawdownPercent = maxDrawdown,
                message = "تم حفظ حدود المخاطر لجلسة Replay"
            )
        }
    }

    fun currentRiskBlockReason(): String? {
        val state = _uiState.value
        if (state.isLoading || state.totalCandles == 0) return "لا توجد جلسة Replay جاهزة"
        return ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(
                enabled = state.riskGuardEnabled,
                maxPositions = state.maxOpenPositions,
                maxOrders = state.maxPendingOrders,
                maxDrawdownPercent = state.maxDrawdownPercent,
                maxConsecutiveLosses = state.maxConsecutiveLosses,
                maxSessionLossUsd = state.maxSessionLossUsd
            ),
            ReplayRiskPolicy.Exposure(
                initialBalance = state.initialBalance,
                balance = state.currentBalance,
                equity = replayAccount().equity,
                openPositions = openPositions.size,
                pendingOrders = pendingOrders.size,
                consecutiveLosses = consecutiveLosses()
            ),
            isPending = false
        )
    }

    private fun canAcceptReplayOrder(isPending: Boolean): Boolean {
        val state = _uiState.value
        val reason = if (state.isLoading || state.totalCandles == 0) {
            "لا توجد جلسة Replay جاهزة"
        } else ReplayRiskPolicy.blockReason(
            ReplayRiskPolicy.Limits(
                enabled = state.riskGuardEnabled,
                maxPositions = state.maxOpenPositions,
                maxOrders = state.maxPendingOrders,
                maxDrawdownPercent = state.maxDrawdownPercent,
                maxConsecutiveLosses = state.maxConsecutiveLosses,
                maxSessionLossUsd = state.maxSessionLossUsd
            ),
            ReplayRiskPolicy.Exposure(
                initialBalance = state.initialBalance,
                balance = state.currentBalance,
                equity = replayAccount().equity,
                openPositions = openPositions.size,
                pendingOrders = pendingOrders.size,
                consecutiveLosses = consecutiveLosses()
            ),
            isPending
        )
        if (reason != null) {
            _uiState.update { it.copy(message = reason) }
            return false
        }
        return true
    }

    fun setInteractionMode(mode: ReplayInteractionMode) {
        replayEngine.pause()
        _uiState.update { it.copy(interactionMode = mode) }
    }

    fun resetReplay() {
        cancelBatchAdvance()
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) {
            _uiState.update { it.copy(message = "لا يمكن إعادة جلسة Replay قبل تحميل الشموع") }
            return
        }
        replayEngine.pause()
        resetReplayAccount()
        nextId = 1L
        accountSnapshots.clear()
        replayEngine.reset()
        saveAccountSnapshot()
    }

    private fun resetReplayAccount() {
        openPositions.clear()
        pendingOrders.clear()
        closedTrades.clear()
        _uiState.update {
            it.copy(
                currentBalance = it.initialBalance,
                currentEquity = it.initialBalance,
                openPositions = emptyList(),
                pendingOrders = emptyList(),
                closedTrades = emptyList(),
                peakEquity = it.initialBalance,
                maxObservedDrawdownPercent = 0.0,
                equitySamples = emptyList()
            )
        }
    }

    private fun replayAccount(balance: Double = _uiState.value.currentBalance): VirtualAccount {
        val equity = ReplayAccountMath.equity(balance, openPositions)
        val usedMargin = ReplayAccountMath.usedMargin(openPositions)
        return VirtualAccount(
            id = 9999,
            name = "حساب محاكاة Replay الافتراضي",
            initialBalance = _uiState.value.initialBalance,
            balance = balance,
            equity = equity,
            margin = usedMargin,
            freeMargin = ReplayAccountMath.freeMargin(balance, openPositions),
            mode = AccountMode.REPLAY
        )
    }

    fun placePendingOrder(
        type: OrderType,
        side: OrderSide,
        volume: Double,
        requestedPrice: Double,
        sl: Double? = null,
        tp: Double? = null
    ) {
        cancelBatchAdvance()
        if (!canAcceptReplayOrder(isPending = true)) return
        replayEngine.pause()
        val tick = replayEngine.currentTick.value
        if (_uiState.value.isLoading || tick == null ||
            !tick.symbol.equals(_uiState.value.symbol, ignoreCase = true) ||
            !com.example.core.market.DataIntegrityValidator.validateTick(tick).isValid ||
            !volume.isFinite() || volume <= 0.0 ||
            !requestedPrice.isFinite() || requestedPrice <= 0.0 ||
            (sl != null && (!sl.isFinite() || sl <= 0.0 ||
                (if (side == OrderSide.BUY) sl >= tick.ask else sl <= tick.bid))) ||
            (tp != null && (!tp.isFinite() || tp <= 0.0 ||
                (if (side == OrderSide.BUY) tp <= tick.ask else tp >= tick.bid))) ||
            type == OrderType.MARKET ||
            (type in listOf(OrderType.BUY_LIMIT, OrderType.BUY_STOP) && side != OrderSide.BUY) ||
            (type in listOf(OrderType.SELL_LIMIT, OrderType.SELL_STOP) && side != OrderSide.SELL)) {
            _uiState.update { it.copy(message = "نوع الأمر المعلق أو سعر Replay غير صالح") }
            return
        }
        val validation = com.example.core.execution.OrderValidator.validate(
            account = replayAccount(),
            symbol = tick.symbol,
            type = type,
            side = side,
            volume = volume,
            tick = tick,
            requestedPrice = requestedPrice,
            stopLoss = sl,
            takeProfit = tp
        )
        if (validation is com.example.core.execution.OrderValidationResult.Rejected) {
            _uiState.update { it.copy(message = validation.message) }
            return
        }
        pendingOrders.add(
            Order(
                id = nextId++,
                accountId = 9999,
                symbol = tick.symbol,
                direction = side,
                type = type,
                volume = volume,
                requestedPrice = requestedPrice,
                stopLoss = sl,
                takeProfit = tp,
                createdAt = tick.timestamp
            )
        )
        _uiState.update {
            it.copy(pendingOrders = pendingOrders.toList(), message = "تم وضع أمر معلق في Replay")
        }
        saveAccountSnapshot()
    }

    fun cancelPendingOrder(orderId: Long) {
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) return
        replayEngine.pause()
        val order = pendingOrders.firstOrNull { it.id == orderId && it.status == OrderStatus.PENDING }
            ?: return
        pendingOrders.remove(order)
        _uiState.update {
            it.copy(pendingOrders = pendingOrders.toList(), message = "تم إلغاء الأمر المعلق #$orderId")
        }
        saveAccountSnapshot()
    }

    fun executeOrder(side: OrderSide, volume: Double = 0.01, sl: Double? = null, tp: Double? = null) {
        // Strategy signals are emitted inside the candle-step callback.
        // Do not cancel the active batch or playback from inside that callback.
        val strategyFill = executingStrategySignal
        if (!strategyFill) cancelBatchAdvance()
        if (!canAcceptReplayOrder(isPending = false)) return
        val candle = replayEngine.currentCandle.value ?: run {
            _uiState.update { it.copy(message = "لا توجد شمعة Replay متاحة للتداول") }
            return
        }
        val tick = replayEngine.currentTick.value ?: run {
            _uiState.update { it.copy(message = "لا يوجد سعر Replay متاح للتداول") }
            return
        }
        if (_uiState.value.isLoading || tick.symbol != _uiState.value.symbol ||
            candle.symbol != tick.symbol ||
            candle.timeframe != _uiState.value.timeframe ||
            !com.example.core.market.DataIntegrityValidator.validateTick(tick).isValid ||
            !volume.isFinite() || volume <= 0.0 ||
            (sl != null && (!sl.isFinite() || sl <= 0.0)) ||
            (tp != null && (!tp.isFinite() || tp <= 0.0))) {
            _uiState.update { it.copy(message = "تعذر تنفيذ الأمر: سعر أو حجم Replay غير صالح") }
            return
        }

        // Do not pause playback for rejected manual orders.
        if (!strategyFill) replayEngine.pause()

        // Use the same equity/margin accounting for manual and pending fills.
        // A stale UI equity snapshot must not overstate available margin.
        val replayAcc = replayAccount()

        val result = executionEngine.executeMarketOrder(
            account = replayAcc,
            symbol = _uiState.value.symbol,
            side = side,
            volume = volume,
            tick = tick,
            stopLoss = sl,
            takeProfit = tp,
            mode = "REPLAY"
        )

        when (result) {
            is com.example.core.execution.ExecutionResult.Success -> {
                val pos = result.position.copy(id = nextId++)
                openPositions.add(pos)
                _uiState.update {
                    it.copy(
                        openPositions = openPositions.toList(),
                        currentEquity = ReplayAccountMath.equity(it.currentBalance, openPositions),
                        message = "تم تنفيذ أمر Replay ${side.displayNameAr} $volume لوت"
                    )
                }
                saveAccountSnapshot()
            }
            is com.example.core.execution.ExecutionResult.Error -> {
                _uiState.update { it.copy(message = result.message) }
            }
            else -> {}
        }
    }

    fun closePosition(posId: Long) {
        cancelBatchAdvance()
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) return
        replayEngine.pause()
        val pos = openPositions.firstOrNull { it.id == posId } ?: run {
            _uiState.update { it.copy(message = "الصفقة غير موجودة في Replay") }
            return
        }
        val tick = replayEngine.currentTick.value
        if (_uiState.value.isLoading || tick == null || tick.symbol != pos.symbol ||
            replayEngine.currentCandle.value?.symbol != pos.symbol ||
            !com.example.core.market.DataIntegrityValidator.validateTick(tick).isValid) {
            _uiState.update { it.copy(message = "لا يمكن إغلاق الصفقة دون سعر Replay صالح") }
            return
        }
        val exitPrice = if (pos.side == PositionSide.BUY) tick.bid else tick.ask
        val candle = replayEngine.currentCandle.value

        val (trade, _) = executionEngine.closePosition(
            position = pos,
            exitPrice = exitPrice,
            exitReason = ExitReason.MANUAL_CLOSE,
            closeTime = candle?.closeTime ?: tick.timestamp
        )
        openPositions.remove(pos)
        closedTrades.add(trade)
        val newBal = ReplayAccountMath.realizedBalance(_uiState.value.currentBalance, trade.netProfitLoss)

        _uiState.update {
            it.copy(
                currentBalance = newBal,
                currentEquity = ReplayAccountMath.equity(newBal, openPositions),
                openPositions = openPositions.toList(),
                closedTrades = closedTrades.toList(),
                message = "تم إغلاق الصفقة #${pos.id} في Replay"
            )
        }
        // Manual close changes realized P&L and the journal at the current index.
        // Persist both so a later rewind cannot restore a stale checkpoint.
        saveAccountSnapshot()
    }

    fun updatePositionProtection(posId: Long, sl: Double?, tp: Double?) {
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) return
        replayEngine.pause()
        val positionIndex = openPositions.indexOfFirst { it.id == posId }
        if (positionIndex < 0) return
        val position = openPositions[positionIndex]
        val tick = replayEngine.currentTick.value
        if (_uiState.value.isLoading || tick == null ||
            !position.symbol.equals(tick.symbol, ignoreCase = true) ||
            !com.example.core.market.DataIntegrityValidator.validateTick(tick).isValid) {
            _uiState.update { it.copy(message = "لا يمكن تعديل الحماية دون سعر Replay صالح") }
            return
        }
        val liquidation = if (position.side == PositionSide.BUY) tick.bid else tick.ask
        val validSl = sl == null || (sl.isFinite() && sl > 0.0 &&
            if (position.side == PositionSide.BUY) sl < liquidation else sl > liquidation)
        val validTp = tp == null || (tp.isFinite() && tp > 0.0 &&
            if (position.side == PositionSide.BUY) tp > liquidation else tp < liquidation)
        if (!validSl || !validTp) {
            _uiState.update { it.copy(message = "مستويات SL/TP غير صالحة بالنسبة لسعر السوق واتجاه الصفقة") }
            return
        }
        openPositions[positionIndex] = position.copy(
            stopLoss = sl,
            takeProfit = tp,
            isBreakEven = position.isBreakEven && sl == position.stopLoss
        )
        _uiState.update {
            it.copy(
                openPositions = openPositions.toList(),
                message = "تم تحديث وقف الخسارة وجني الأرباح للصفقة #$posId"
            )
        }
        saveAccountSnapshot()
    }

    fun setBreakEven(posId: Long) {
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) return
        replayEngine.pause()
        val pos = openPositions.firstOrNull { it.id == posId } ?: return
        val tick = replayEngine.currentTick.value
        if (_uiState.value.isLoading || tick == null || tick.symbol != pos.symbol ||
            !com.example.core.market.DataIntegrityValidator.validateTick(tick).isValid) {
            _uiState.update { it.copy(message = "سعر Replay غير صالح لتفعيل التعادل") }
            return
        }

        val beResult = executionEngine.calculateBreakEven(pos, tick)
        beResult.onSuccess { bePrice ->
            val idx = openPositions.indexOf(pos)
            if (idx != -1) {
                openPositions[idx] = pos.copy(stopLoss = bePrice, isBreakEven = true)
                _uiState.update {
                    it.copy(
                        openPositions = openPositions.toList(),
                        message = "تم نقل وقف الخسارة إلى نقطة التعادل ($bePrice)"
                    )
                }
                saveAccountSnapshot()
            }
        }.onFailure { err ->
            _uiState.update { it.copy(message = err.message ?: "فشل تفعيل نقطة التعادل") }
        }
    }

    private var executingStrategySignal = false

    private fun evaluateOnReplayCandle(candle: Candle, tick: Tick, dataView: ReplayDataView) {
        var curBal = _uiState.value.currentBalance

        // 1. Evaluate open positions with conservative intrabar risk policy
        val iterator = openPositions.listIterator()
        while (iterator.hasNext()) {
            val pos = iterator.next()
            when (val eval = replayEngine.evaluatePositionConservative(pos, candle)) {
                is PositionEvaluation.TriggerClose -> {
                    val (trade, _) = executionEngine.closePosition(
                        position = pos,
                        exitPrice = eval.exitPrice,
                        exitReason = eval.exitReason,
                        closeTime = candle.closeTime
                    )
                    closedTrades.add(trade)
                    curBal = ReplayAccountMath.realizedBalance(curBal, trade.netProfitLoss)
                    iterator.remove()
                }
                is PositionEvaluation.KeepOpen -> {
                    // Replace the exact position under iteration. indexOf()
                    // scans the list and can target the wrong equal-valued
                    // position; ListIterator.set is O(1) and stable.
                    iterator.set(eval.updatedPosition)
                }
            }
        }

        // Settle closed trades and mark remaining positions to market BEFORE strategy
        // execution. Otherwise executeOrder() reads the previous candle's balance
        // and equity, and may reject valid orders or accept orders on stale margin.
        _uiState.update {
            it.copy(
                currentBalance = curBal,
                currentEquity = ReplayAccountMath.equity(curBal, openPositions),
                openPositions = openPositions.toList(),
                closedTrades = closedTrades.toList()
            )
        }

        // Fill waiting orders at the revealed replay quote, not a future candle.
        // Each fill is removed from pendingOrders before the next replay step,
        // so a filled order cannot execute a second time.
        val pendingIterator = pendingOrders.iterator()
        while (pendingIterator.hasNext()) {
            val order = pendingIterator.next()
            val historicalFill = replayEngine.pendingOrderFillPrice(order, candle) ?: continue
            val state = _uiState.value
            // Re-evaluate after every fill, using the latest positions and equity.
            // Blocked pending orders remain pending, never silently discarded.
            val blockReason = ReplayRiskPolicy.blockReason(
                ReplayRiskPolicy.Limits(
                    enabled = state.riskGuardEnabled,
                    maxPositions = state.maxOpenPositions,
                    maxOrders = state.maxPendingOrders,
                    maxDrawdownPercent = state.maxDrawdownPercent,
                    maxConsecutiveLosses = state.maxConsecutiveLosses,
                    maxSessionLossUsd = state.maxSessionLossUsd
                ),
                ReplayRiskPolicy.Exposure(
                    initialBalance = state.initialBalance,
                    balance = curBal,
                    equity = ReplayAccountMath.equity(curBal, openPositions),
                    openPositions = openPositions.size,
                    pendingOrders = pendingOrders.size,
                    consecutiveLosses = consecutiveLosses()
                ),
                isPending = false
            )
            if (blockReason != null) continue
            // Recompute margin after every successful fill. Reusing the same
            // account snapshot for all orders lets multiple pending orders each
            // spend the same available free margin on a single candle.
            // Historical OHLC may touch a pending level even when the bar closes
            // away from it. Never use the closing quote as the trigger.
            val result = executionEngine.evaluatePendingOrder(
                order, tick, replayAccount(curBal), mode = "REPLAY",
                historicalFillPrice = historicalFill
            )
            when (result) {
                is com.example.core.execution.ExecutionResult.Success -> {
                    openPositions.add(result.position.copy(id = nextId++))
                    pendingIterator.remove()
                    // Persist the changed margin/equity before checking the next
                    // pending order, including multiple triggers on this bar.
                    _uiState.update {
                        it.copy(
                            openPositions = openPositions.toList(),
                            currentEquity = ReplayAccountMath.equity(curBal, openPositions),
                            pendingOrders = pendingOrders.toList()
                        )
                    }
                }
                is com.example.core.execution.ExecutionResult.Error -> {
                    // Keep a triggered but unfundable order pending: it may become
                    // executable after other positions close and release margin.
                }
                else -> {}
            }
        }
        _uiState.update {
            it.copy(
                currentBalance = curBal,
                currentEquity = ReplayAccountMath.equity(curBal, openPositions),
                openPositions = openPositions.toList(),
                pendingOrders = pendingOrders.toList()
            )
        }

        // 2. Evaluate Strategy if in STRATEGY mode (strictly using ReplayDataView)
        var lastSignalText: String? = null
        val strat = activeStrategy
        if (_uiState.value.interactionMode == ReplayInteractionMode.STRATEGY && strat != null) {
            val visible = dataView.getVisibleCandles()
            if (visible.size >= 25) {
                val replayAcc = VirtualAccount(
                    id = 9999,
                    name = "Strategy Replay Account",
                    balance = curBal,
                    equity = ReplayAccountMath.equity(curBal, openPositions),
                    margin = ReplayAccountMath.usedMargin(openPositions),
                    freeMargin = ReplayAccountMath.freeMargin(curBal, openPositions)
                )
                val context = StrategyContext(
                    symbol = candle.symbol,
                    timeframe = candle.timeframe,
                    currentCandle = candle,
                    historicalCandles = visible,
                    openPositions = openPositions.toList(),
                    account = replayAcc,
                    latestTick = tick
                )
                val signal = strat.onCandle(context, strat.defaultParameters)
                if (signal.action != SignalAction.HOLD) {
                    lastSignalText = "إشارة ${signal.action}: ${signal.reason}"
                    if (signal.action == SignalAction.BUY && openPositions.none { it.side == PositionSide.BUY }) {
                        executingStrategySignal = true
                        try { executeOrder(OrderSide.BUY, 0.01) }
                        finally { executingStrategySignal = false }
                    } else if (signal.action == SignalAction.SELL && openPositions.none { it.side == PositionSide.SELL }) {
                        executingStrategySignal = true
                        try { executeOrder(OrderSide.SELL, 0.01) }
                        finally { executingStrategySignal = false }
                    }
                }
            }
        }

        val curEq = ReplayAccountMath.equity(curBal, openPositions)

        // 3. Record snapshot checkpoint for safe rollback
        replayEngine.recordCheckpoint(
            ReplayCheckpoint(
                sessionId = 1,
                candleIndex = replayEngine.currentIndex.value,
                timestamp = candle.closeTime,
                balance = curBal,
                equity = curEq,
                openPositions = openPositions.toList(),
                closedTradesCount = closedTrades.size
            )
        )

        _uiState.update {
            it.copy(
                currentBalance = curBal,
                currentEquity = curEq,
                openPositions = openPositions.toList(),
                closedTrades = closedTrades.toList(),
                lastSignalMessage = lastSignalText ?: it.lastSignalMessage
            )
        }
        recordEquitySample(curBal, curEq)
        saveAccountSnapshot()
    }

    private fun recordEquitySample(balance: Double, equity: Double) {
        if (!balance.isFinite() || !equity.isFinite()) return
        val index = replayEngine.currentIndex.value
        _uiState.update { state ->
            // A manual trade can replace an existing candle checkpoint, or a
            // rewind can fork the timeline. Derive the high-water mark from the
            // retained prefix instead of carrying a peak from an abandoned future.
            val history = state.equitySamples
            val prefix = when {
                history.isEmpty() -> history
                history.last().candleIndex < index -> history
                history.last().candleIndex == index -> history.dropLast(1)
                else -> {
                    // Binary-search the sorted timeline rather than scanning all
                    // historical samples after a rewind or a timeline fork.
                    var low = 0
                    var high = history.size
                    while (low < high) {
                        val middle = (low + high) ushr 1
                        if (history[middle].candleIndex < index) low = middle + 1
                        else high = middle
                    }
                    history.subList(0, low)
                }
            }
            // Append-only replay advances are the hot path. Existing high-water
            // marks and worst drawdown are already exact for that prefix.
            // Recompute only when replacing a bar or forking a rewound timeline.
            val appendOnly = prefix === history
            var previousPeak = state.initialBalance
            var previousWorst = 0.0
            if (appendOnly) {
                previousPeak = state.peakEquity
                previousWorst = state.maxObservedDrawdownPercent
            } else {
                for (sample in prefix) {
                    previousPeak = maxOf(previousPeak, sample.equity)
                    if (previousPeak > 0.0) {
                        previousWorst = maxOf(previousWorst,
                            (previousPeak - sample.equity).coerceAtLeast(0.0) * 100.0 / previousPeak)
                    }
                }
            }
            val peak = maxOf(previousPeak, equity)
            val drawdown = if (peak > 0.0) (peak - equity).coerceAtLeast(0.0) * 100.0 / peak else 0.0
            // The replay cursor normally moves forward one bar. Reuse the
            // existing immutable prefix instead of filtering the entire session
            // on every candle (quadratic work for long 5000-bar replays).
            val samples = prefix + ReplayEquitySample(index, equity, balance)
            val worstDrawdown = maxOf(previousWorst, drawdown)
            state.copy(
                peakEquity = peak,
                maxObservedDrawdownPercent = worstDrawdown,
                equitySamples = samples
            )
        }
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }
}
