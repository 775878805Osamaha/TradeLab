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
    val currentBalance: Double = 50.0,
    val currentEquity: Double = 50.0,
    val visibleCandles: List<Candle> = emptyList(),
    val currentCandle: Candle? = null,
    val latestTick: Tick? = null,
    val openPositions: List<Position> = emptyList(),
    val pendingOrders: List<Order> = emptyList(),
    val closedTrades: List<TradeJournalEntry> = emptyList(),
    val isPlaying: Boolean = false,
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
    private val accountSnapshots = mutableMapOf<Int, AccountSnapshot>()

    private fun saveAccountSnapshot() {
        val index = replayEngine.currentIndex.value
        // Any new execution or account edit forks the timeline at this bar.
        // Checkpoints from a previous future must never be restored.
        accountSnapshots.keys.removeAll { it > index }
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

    fun loadReplayData(
        symbol: String = "BTCUSDT",
        tf: Timeframe = Timeframe.M15,
        historyBars: Int = _uiState.value.requestedHistoryBars,
        endOffsetBars: Int = _uiState.value.historyEndOffsetBars
    ) {
        require(endOffsetBars in 0..100_000) { "Historical offset must be 0 to 100000 bars" }
        require(historyBars in 50..5_000) { "Replay history must contain 50 to 5000 bars" }
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
        if (symbol !in setOf("BTCUSDT", "ETHUSDT")) {
            _uiState.update {
                it.copy(isLoading = false, message = "لا تتوفر بيانات تاريخية معتمدة لهذا الرمز. اختر BTCUSDT أو ETHUSDT.")
            }
            return
        }
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
                        it.copy(isLoading = false, message = "لا توجد شموع تاريخية موثوقة لهذا الرمز. اختر BTCUSDT أو ETHUSDT.")
                    }
                    return@launch
                }
                // A superseded request must not initialize the engine with the old instrument.
                if (_uiState.value.symbol != symbol ||
                    _uiState.value.timeframe != tf ||
                    _uiState.value.requestedHistoryBars != historyBars ||
                    _uiState.value.historyEndOffsetBars != endOffsetBars) return@launch
                if (candles.any { it.symbol != symbol || it.timeframe != tf } ||
                    candles.zipWithNext().any { (a, b) -> b.openTime <= a.openTime }) {
                    _uiState.update { it.copy(isLoading = false, message = "بيانات Replay غير متسقة؛ أُلغيت الجلسة لحماية نتائج الاختبار") }
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
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) {
            _uiState.update { it.copy(message = "انتظر اكتمال تحميل بيانات Replay أولًا") }
            return
        }
        replayEngine.play()
    }
    fun pause() = replayEngine.pause()
    fun stepForward() {
        if (_uiState.value.isLoading || _uiState.value.totalCandles == 0) {
            _uiState.update { it.copy(message = "لا توجد شموع Replay جاهزة للتقدم") }
            return
        }
        replayEngine.stepForward()
    }

    fun stepBackward() {
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
            accountSnapshots.keys.removeAll { it > targetIndex }
            // Invalidate the engine's separate checkpoint cache too.
            replayEngine.discardCheckpointsAfter(targetIndex)
            _uiState.update { it.copy(message = "تمت استعادة حالة الحساب عند الشمعة #$targetIndex") }
        }
    }

    fun jumpToTimestamp(timestamp: Long) {
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
        if (!sp.isFinite() || sp <= 0f) {
            _uiState.update { it.copy(message = "سرعة Replay يجب أن تكون موجبة وصالحة") }
            return
        }
        replayEngine.setSpeed(sp)
    }

    fun configureRiskLimits(maxPositions: Int, maxOrders: Int, maxDrawdown: Double) {
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

    private fun canAcceptReplayOrder(isPending: Boolean): Boolean {
        val state = _uiState.value
        val drawdown = if (state.initialBalance > 0.0) {
            (state.initialBalance - state.currentEquity) * 100.0 / state.initialBalance
        } else 100.0
        val reason = when {
            state.isLoading || state.totalCandles == 0 -> "لا توجد جلسة Replay جاهزة"
            drawdown >= state.maxDrawdownPercent -> "تم بلوغ حد التراجع المسموح في جلسة Replay"
            isPending && pendingOrders.size >= state.maxPendingOrders -> "تم بلوغ الحد الأقصى للأوامر المعلقة"
            !isPending && openPositions.size >= state.maxOpenPositions -> "تم بلوغ الحد الأقصى للصفقات المفتوحة"
            else -> null
        }
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
        val usedMargin = openPositions.sumOf { it.margin }
        return VirtualAccount(
            id = 9999,
            name = "حساب محاكاة Replay الافتراضي",
            initialBalance = _uiState.value.initialBalance,
            balance = balance,
            equity = equity,
            margin = usedMargin,
            freeMargin = maxOf(0.0, equity - usedMargin),
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
        if (!canAcceptReplayOrder(isPending = true)) return
        replayEngine.pause()
        val tick = replayEngine.currentTick.value
        if (_uiState.value.isLoading || tick == null ||
            !tick.symbol.equals(_uiState.value.symbol, ignoreCase = true) ||
            !com.example.core.market.DataIntegrityValidator.validateTick(tick).isValid ||
            !volume.isFinite() || volume <= 0.0 ||
            !requestedPrice.isFinite() || requestedPrice <= 0.0 ||
            (sl != null && (!sl.isFinite() || sl <= 0.0)) ||
            (tp != null && (!tp.isFinite() || tp <= 0.0)) ||
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
        if (!canAcceptReplayOrder(isPending = false)) return
        replayEngine.pause()
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
            closeTime = candle?.openTime ?: System.currentTimeMillis()
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

    private fun evaluateOnReplayCandle(candle: Candle, tick: Tick, dataView: ReplayDataView) {
        var curBal = _uiState.value.currentBalance

        // 1. Evaluate open positions with conservative intrabar risk policy
        val iterator = openPositions.iterator()
        while (iterator.hasNext()) {
            val pos = iterator.next()
            when (val eval = replayEngine.evaluatePositionConservative(pos, candle)) {
                is PositionEvaluation.TriggerClose -> {
                    val (trade, _) = executionEngine.closePosition(
                        position = pos,
                        exitPrice = eval.exitPrice,
                        exitReason = eval.exitReason,
                        closeTime = candle.openTime
                    )
                    closedTrades.add(trade)
                    curBal = ReplayAccountMath.realizedBalance(curBal, trade.netProfitLoss)
                    iterator.remove()
                }
                is PositionEvaluation.KeepOpen -> {
                    val idx = openPositions.indexOf(pos)
                    if (idx != -1) {
                        openPositions[idx] = eval.updatedPosition
                    }
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
            val state = _uiState.value
            val equityNow = ReplayAccountMath.equity(curBal, openPositions)
            val drawdownNow = if (state.initialBalance > 0.0) {
                (state.initialBalance - equityNow) * 100.0 / state.initialBalance
            } else 100.0
            // Do not open additional positions after the risk guard is hit.
            // Keep the orders pending so the user can inspect or cancel them.
            if (openPositions.size >= state.maxOpenPositions ||
                drawdownNow >= state.maxDrawdownPercent) continue
            // Recompute margin after every successful fill. Reusing the same
            // account snapshot for all orders lets multiple pending orders each
            // spend the same available free margin on a single candle.
            val result = executionEngine.evaluatePendingOrder(
                order, tick, replayAccount(curBal), mode = "REPLAY"
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
                    margin = openPositions.sumOf { it.margin },
                    freeMargin = maxOf(0.0, ReplayAccountMath.equity(curBal, openPositions) - openPositions.sumOf { it.margin })
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
                        executeOrder(OrderSide.BUY, 0.01)
                    } else if (signal.action == SignalAction.SELL && openPositions.none { it.side == PositionSide.SELL }) {
                        executeOrder(OrderSide.SELL, 0.01)
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
                timestamp = candle.openTime,
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
            val previousPeak = state.peakEquity.coerceAtLeast(state.initialBalance)
            val peak = maxOf(previousPeak, equity)
            val drawdown = if (peak > 0.0) (peak - equity).coerceAtLeast(0.0) * 100.0 / peak else 0.0
            val samples = state.equitySamples.filter { it.candleIndex < index } +
                ReplayEquitySample(index, equity, balance)
            state.copy(
                peakEquity = peak,
                maxObservedDrawdownPercent = maxOf(state.maxObservedDrawdownPercent, drawdown),
                equitySamples = samples
            )
        }
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }
}
