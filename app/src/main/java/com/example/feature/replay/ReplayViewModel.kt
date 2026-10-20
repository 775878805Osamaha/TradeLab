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
    val currentReplayTime: Long = 0L,
    val interactionMode: ReplayInteractionMode = ReplayInteractionMode.MANUAL,
    val selectedStrategyName: String? = null,
    val lastSignalMessage: String? = null,
    val isLoading: Boolean = false,
    val message: String? = null
)

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
        val nextOrderId: Long
    )
    private val accountSnapshots = mutableMapOf<Int, AccountSnapshot>()

    private fun saveAccountSnapshot() {
        accountSnapshots[replayEngine.currentIndex.value] = AccountSnapshot(
            balance = _uiState.value.currentBalance,
            equity = _uiState.value.currentEquity,
            positions = openPositions.toList(),
            orders = pendingOrders.toList(),
            trades = closedTrades.toList(),
            nextOrderId = nextId
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
                closedTrades = closedTrades.toList()
            )
        }
    }

    private var activeStrategy: Strategy? = null

    fun setStrategy(strategy: Strategy?) {
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

    fun loadReplayData(symbol: String = "BTCUSDT", tf: Timeframe = Timeframe.M15) {
        replayLoadJob?.cancel()
        replayEngine.pause()
        // A new dataset must never inherit positions, pending orders, journal or IDs
        // from the previous replay session, even if loading subsequently fails.
        resetReplayAccount()
        nextId = 1L
        accountSnapshots.clear()
        // Do not continue displaying a previous instrument's replay while switching.
        _uiState.update {
            it.copy(
                symbol = symbol, timeframe = tf, isLoading = true, message = null,
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
                val interval = tf.minutes * 60 * 1000L
                val from = now - (interval * 300)
                val candles = marketDataRepository.getCandles(symbol, tf, from, now)
                if (candles.isEmpty()) {
                    _uiState.update {
                        it.copy(isLoading = false, message = "لا توجد شموع تاريخية موثوقة لهذا الرمز. اختر BTCUSDT أو ETHUSDT.")
                    }
                    return@launch
                }
                replayEngine.initialize(candles, startIndex = minOf(20, candles.lastIndex))
                _uiState.update { it.copy(isLoading = false) }
                saveAccountSnapshot()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        message = "تعذر تحميل بيانات إعادة العرض لهذا الرمز. اختر BTCUSDT أو ETHUSDT وتحقق من الاتصال."
                    )
                }
            }
        }
    }

    fun play() = replayEngine.play()
    fun pause() = replayEngine.pause()
    fun stepForward() = replayEngine.stepForward()

    fun stepBackward() {
        replayEngine.pause()
        val targetIndex = replayEngine.currentIndex.value - 1
        if (targetIndex < 1) {
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
            _uiState.update { it.copy(message = "تمت استعادة حالة الحساب عند الشمعة #$targetIndex") }
        }
    }

    fun jumpToTimestamp(timestamp: Long) {
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

    fun setSpeed(sp: Float) = replayEngine.setSpeed(sp)

    fun setInteractionMode(mode: ReplayInteractionMode) {
        _uiState.update { it.copy(interactionMode = mode) }
    }

    fun resetReplay() {
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
                closedTrades = emptyList()
            )
        }
    }

    fun executeOrder(side: OrderSide, volume: Double = 0.01, sl: Double? = null, tp: Double? = null) {
        val candle = replayEngine.currentCandle.value ?: return
        val tick = replayEngine.currentTick.value ?: return
        if (_uiState.value.isLoading || tick.symbol != _uiState.value.symbol ||
            candle.symbol != tick.symbol ||
            !com.example.core.market.DataIntegrityValidator.validateTick(tick).isValid ||
            !volume.isFinite() || volume <= 0.0) {
            _uiState.update { it.copy(message = "تعذر تنفيذ الأمر: سعر أو حجم Replay غير صالح") }
            return
        }

        // Isolated Replay Account
        val replayAcc = VirtualAccount(
            id = 9999,
            name = "حساب محاكاة Replay الافتراضي",
            initialBalance = _uiState.value.initialBalance,
            balance = _uiState.value.currentBalance,
            equity = _uiState.value.currentEquity,
            margin = openPositions.sumOf { it.margin },
            freeMargin = maxOf(0.0, _uiState.value.currentEquity - openPositions.sumOf { it.margin }),
            mode = AccountMode.REPLAY
        )

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
        val pos = openPositions.firstOrNull { it.id == posId } ?: return
        val tick = replayEngine.currentTick.value
        if (tick == null || tick.symbol != pos.symbol ||
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

    fun setBreakEven(posId: Long) {
        val pos = openPositions.firstOrNull { it.id == posId } ?: return
        val tick = replayEngine.currentTick.value ?: return
        if (tick.symbol != pos.symbol ||
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
        saveAccountSnapshot()
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }
}
