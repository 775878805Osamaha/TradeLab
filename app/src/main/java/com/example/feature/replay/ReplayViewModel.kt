package com.example.feature.replay

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.execution.ExecutionEngine
import com.example.core.execution.PositionEvaluation
import com.example.core.model.*
import com.example.core.replay.HistoricalReplayEngine
import com.example.core.replay.ReplayDataView
import com.example.core.strategy.EmaCrossoverStrategy
import com.example.core.strategy.SignalAction
import com.example.core.strategy.Strategy
import com.example.core.strategy.StrategyContext
import com.example.data.repository.MarketDataRepository
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

enum class ReplayInteractionMode {
    MANUAL,
    STRATEGY
}

data class ReplayUiState(
    val symbol: String = "XAUUSD",
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
    val selectedStrategyName: String = "تقاطع المتوسطات EMA Crossover",
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

    private val activeStrategy: Strategy = EmaCrossoverStrategy()

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

    fun loadReplayData(symbol: String = "XAUUSD", tf: Timeframe = Timeframe.M15) {
        _uiState.update { it.copy(symbol = symbol, timeframe = tf, isLoading = true) }
        viewModelScope.launch {
            val now = System.currentTimeMillis()
            val interval = tf.minutes * 60 * 1000L
            val from = now - (interval * 300)

            val candles = marketDataRepository.getCandles(symbol, tf, from, now)
            replayEngine.initialize(candles, startIndex = 20)
            resetReplayAccount()
            _uiState.update { it.copy(isLoading = false) }
        }
    }

    fun play() = replayEngine.play()
    fun pause() = replayEngine.pause()
    fun stepForward() = replayEngine.stepForward()

    fun stepBackward() {
        val targetIdx = replayEngine.currentIndex.value - 1
        val checkpoint = replayEngine.getCheckpoint(targetIdx)
        if (checkpoint != null) {
            // Restore safe checkpoint
            openPositions.clear()
            openPositions.addAll(checkpoint.openPositions)
            _uiState.update {
                it.copy(
                    currentBalance = checkpoint.balance,
                    currentEquity = checkpoint.equity,
                    openPositions = openPositions.toList()
                )
            }
        }
        replayEngine.stepBackward()
    }

    fun jumpToTimestamp(timestamp: Long) {
        replayEngine.jumpToTimestamp(timestamp)
    }

    fun setSpeed(sp: Float) = replayEngine.setSpeed(sp)

    fun setInteractionMode(mode: ReplayInteractionMode) {
        _uiState.update { it.copy(interactionMode = mode) }
    }

    fun resetReplay() {
        replayEngine.reset()
        resetReplayAccount()
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
        val candle = _uiState.value.currentCandle ?: return
        val tick = _uiState.value.latestTick ?: return

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
                        message = "تم تنفيذ أمر Replay ${side.displayNameAr} $volume لوت"
                    )
                }
            }
            is com.example.core.execution.ExecutionResult.Error -> {
                _uiState.update { it.copy(message = result.message) }
            }
            else -> {}
        }
    }

    fun closePosition(posId: Long) {
        val pos = openPositions.firstOrNull { it.id == posId } ?: return
        val tick = _uiState.value.latestTick
        val exitPrice = if (pos.side == PositionSide.BUY) (tick?.bid ?: pos.currentPrice) else (tick?.ask ?: pos.currentPrice)
        val candle = _uiState.value.currentCandle

        val (trade, _) = executionEngine.closePosition(
            position = pos,
            exitPrice = exitPrice,
            exitReason = ExitReason.MANUAL_CLOSE,
            closeTime = candle?.openTime ?: System.currentTimeMillis()
        )
        openPositions.remove(pos)
        closedTrades.add(trade)
        val newBal = _uiState.value.currentBalance + trade.netProfitLoss

        _uiState.update {
            it.copy(
                currentBalance = newBal,
                openPositions = openPositions.toList(),
                closedTrades = closedTrades.toList(),
                message = "تم إغلاق الصفقة #${pos.id} في Replay"
            )
        }
    }

    fun setBreakEven(posId: Long) {
        val pos = openPositions.firstOrNull { it.id == posId } ?: return
        val tick = _uiState.value.latestTick ?: return

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
                    curBal += trade.netProfitLoss
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

        // 2. Evaluate Strategy if in STRATEGY mode (strictly using ReplayDataView)
        var lastSignalText: String? = null
        if (_uiState.value.interactionMode == ReplayInteractionMode.STRATEGY) {
            val visible = dataView.getVisibleCandles()
            if (visible.size >= 25) {
                val replayAcc = VirtualAccount(
                    id = 9999,
                    name = "Strategy Replay Account",
                    balance = curBal,
                    equity = curBal + openPositions.sumOf { it.profitLoss },
                    margin = openPositions.sumOf { it.margin },
                    freeMargin = maxOf(0.0, curBal - openPositions.sumOf { it.margin })
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
                val signal = activeStrategy.onCandle(context, activeStrategy.defaultParameters)
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

        val floatingPl = openPositions.sumOf { it.profitLoss }
        val curEq = curBal + floatingPl

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
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }
}
