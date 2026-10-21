package com.example.core.replay

import com.example.core.execution.PositionEvaluation
import com.example.core.market.DataIntegrityValidator
import com.example.core.market.DefaultSymbols
import com.example.core.model.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.ConcurrentHashMap

/**
 * Historical Market Replay Engine.
 * 
 * CORE REPLAY PRINCIPLE:
 * At replay time T, information > T is strictly forbidden.
 * Data access is enforced through [ReplayDataView] at the data layer, not just hidden visually.
 * 
 * INTRABAR CONSERVATIVE EXECUTION POLICY:
 * If both Stop Loss and Take Profit could have been reached inside the same candle bar
 * (candle.low <= SL && candle.high >= TP) and exact tick sequence is unavailable:
 * Stop Loss is deterministically assumed to execute first (worst-case risk principle).
 * The same candle always produces the exact same deterministic result.
 */
class HistoricalReplayEngine(
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
) {
    val replayClock = ReplayClock(scope)

    private var allCandles: List<Candle> = emptyList()
    private val checkpoints = ConcurrentHashMap<Int, ReplayCheckpoint>()

    private val _visibleCandles = MutableStateFlow<List<Candle>>(emptyList())
    val visibleCandles: StateFlow<List<Candle>> = _visibleCandles.asStateFlow()

    private val _currentCandle = MutableStateFlow<Candle?>(null)
    val currentCandle: StateFlow<Candle?> = _currentCandle.asStateFlow()

    private val _currentTick = MutableStateFlow<Tick?>(null)
    val currentTick: StateFlow<Tick?> = _currentTick.asStateFlow()

    private val _currentIndex = MutableStateFlow(0)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    private val _totalCandles = MutableStateFlow(0)
    val totalCandles: StateFlow<Int> = _totalCandles.asStateFlow()

    private val _status = MutableStateFlow(ReplayStatus.READY)
    val status: StateFlow<ReplayStatus> = _status.asStateFlow()

    // Pass through clock states
    val isPlaying: StateFlow<Boolean> = replayClock.isRunning
    val speed: StateFlow<Float> = replayClock.speed
    val currentReplayTime: StateFlow<Long> = replayClock.currentTime

    var onCandleRevealed: ((Candle, Tick, ReplayDataView) -> Unit)? = null

    init {
        replayClock.onTickStep = {
            withContext(Dispatchers.Main) {
                stepForward()
            }
        }
    }

    /**
     * Initializes replay with historical candles up to the chosen starting index.
     * Sanitizes dataset using DataIntegrityValidator to eliminate corrupted or duplicate bars.
     */
    fun initialize(candles: List<Candle>, startIndex: Int = 10) {
        pause()
        checkpoints.clear()
        allCandles = DataIntegrityValidator.sanitizeCandles(candles)
        _totalCandles.value = allCandles.size

        val safeStart = startIndex.coerceIn(0, (allCandles.size - 1).coerceAtLeast(0))
        _currentIndex.value = safeStart
        _status.value = ReplayStatus.READY

        if (allCandles.isNotEmpty()) {
            replayClock.initialize(allCandles[safeStart].openTime)
        }

        // Loading a dataset positions the cursor; it must not trade on the
        // initial candle before the replay account is ready.
        updateVisibleState(evaluateTrades = false)
    }

    /**
     * Provides strict ReplayDataView. Any call attempting to access future candles throws ReplayBoundaryViolation.
     */
    fun getReplayDataView(): ReplayDataView {
        return ReplayDataView(
            allCandles = allCandles,
            currentIndex = _currentIndex.value,
            currentTick = _currentTick.value
        )
    }

    fun play() {
        if (allCandles.isEmpty()) return
        _status.value = ReplayStatus.RUNNING
        replayClock.play()
    }

    fun pause() {
        replayClock.pause()
        if (_status.value == ReplayStatus.RUNNING) {
            _status.value = ReplayStatus.PAUSED
        }
    }

    fun stepForward(): Boolean {
        if (_currentIndex.value < allCandles.size - 1) {
            _currentIndex.value++
            updateVisibleState()
            return true
        }
        pause()
        _status.value = ReplayStatus.COMPLETED
        return false
    }

    /**
     * Reverses replay by one candle safely.
     */
    fun stepBackward(): Boolean {
        if (_currentIndex.value > 0) {
            _currentIndex.value--
            // Rewinding only restores chart/clock; ViewModel restores the financial
            // snapshot. Re-running strategies or SL/TP here corrupts trade history.
            updateVisibleState(evaluateTrades = false)
            return true
        }
        return false
    }

    fun jumpToIndex(targetIndex: Int) {
        if (allCandles.isEmpty()) return
        // A seek skips candle execution, so no financial checkpoint from the
        // old cursor path may be considered valid at the destination.
        pause()
        checkpoints.clear()
        val clamped = targetIndex.coerceIn(0, allCandles.size - 1)
        _currentIndex.value = clamped
        // A seek is navigation, not a candle execution. Executing a strategy
        // only on the destination candle would silently skip intermediate bars.
        updateVisibleState(evaluateTrades = false)
    }

    fun jumpToTimestamp(targetTimestamp: Long) {
        if (allCandles.isEmpty()) return
        // Candles are sanitized into chronological order on initialize().
        // Binary search avoids scanning the entire history for each seek.
        var low = 0
        var high = allCandles.size
        while (low < high) {
            val mid = low + (high - low) / 2
            if (allCandles[mid].openTime < targetTimestamp) low = mid + 1
            else high = mid
        }
        jumpToIndex(low.coerceAtMost(allCandles.lastIndex))
    }

    fun setSpeed(speedFactor: Float) {
        replayClock.setSpeed(speedFactor)
    }

    fun clear() {
        pause()
        checkpoints.clear()
        allCandles = emptyList()
        _totalCandles.value = 0
        _currentIndex.value = 0
        _visibleCandles.value = emptyList()
        _currentCandle.value = null
        _currentTick.value = null
        _status.value = ReplayStatus.READY
    }

    fun reset() {
        pause()
        checkpoints.clear()
        _currentIndex.value = if (allCandles.isNotEmpty()) minOf(10, allCandles.size - 1) else 0
        _status.value = ReplayStatus.READY
        // Reset is navigation, not a new strategy signal or SL/TP event.
        updateVisibleState(evaluateTrades = false)
    }

    /**
     * Saves a snapshot checkpoint for safe rollback and crash recovery.
     */
    fun recordCheckpoint(checkpoint: ReplayCheckpoint) {
        checkpoints[checkpoint.candleIndex] = checkpoint
    }

    fun getCheckpoint(candleIndex: Int): ReplayCheckpoint? {
        return checkpoints[candleIndex]
    }

    /**
     * Drop snapshots from the abandoned future after a financial rollback.
     * Without this, getCheckpoint() could return balances from a discarded
     * trading timeline after the user takes different trades.
     */
    fun discardCheckpointsAfter(candleIndex: Int) {
        checkpoints.keys.removeAll { it > candleIndex }
    }

    /**
     * Evaluates open position SL/TP against a replay candle under the conservative execution policy.
     * If both SL and TP are touched inside the same candle: SL triggers first.
     */
    fun evaluatePositionConservative(
        position: Position,
        candle: Candle
    ): PositionEvaluation {
        // A candle from another instrument must never trigger this position's
        // stops or overwrite its mark-to-market P&L.
        require(position.symbol.equals(candle.symbol, ignoreCase = true)) {
            "Replay candle symbol does not match position"
        }
        require(position.volume.isFinite() && position.volume > 0.0 &&
            position.entryPrice.isFinite() && position.entryPrice > 0.0 &&
            candle.low.isFinite() && candle.high.isFinite() &&
            candle.close.isFinite() && candle.low > 0.0 &&
            candle.high >= candle.low && candle.close > 0.0) {
            "Invalid replay position or candle"
        }
        val sl = position.stopLoss
        val tp = position.takeProfit
        require((sl == null || (sl.isFinite() && sl > 0.0)) &&
            (tp == null || (tp.isFinite() && tp > 0.0))) {
            "Invalid replay stop-loss or take-profit level"
        }
        require(candle.open.isFinite() && candle.open > 0.0 &&
            candle.open in candle.low..candle.high &&
            candle.close in candle.low..candle.high) {
            "Replay OHLC candle range is inconsistent"
        }

        val isSlTouched = when (position.side) {
            PositionSide.BUY -> sl != null && candle.low <= sl
            PositionSide.SELL -> sl != null && candle.high >= sl
        }

        val isTpTouched = when (position.side) {
            PositionSide.BUY -> tp != null && candle.high >= tp
            PositionSide.SELL -> tp != null && candle.low <= tp
        }

        // Intrabar collision resolution: conservative risk policy (Stop Loss triggers first)
        if (isSlTouched && isTpTouched) {
            return PositionEvaluation.TriggerClose(
                exitPrice = sl!!,
                exitReason = if (position.isBreakEven) ExitReason.BREAK_EVEN else ExitReason.STOP_LOSS
            )
        }

        if (isSlTouched) {
            return PositionEvaluation.TriggerClose(
                exitPrice = sl!!,
                exitReason = if (position.isBreakEven) ExitReason.BREAK_EVEN else ExitReason.STOP_LOSS
            )
        }

        if (isTpTouched) {
            return PositionEvaluation.TriggerClose(
                exitPrice = tp!!,
                exitReason = ExitReason.TAKE_PROFIT
            )
        }

        val symInfo = DefaultSymbols.getSymbol(position.symbol)
        // Mark a BUY at executable Bid and a SELL at executable Ask. Using
        // the midpoint (candle.close) incorrectly inflates replay equity by
        // ignoring the spread that a manual market close would actually pay.
        val halfSpread = symInfo.defaultSpreadPips * symInfo.pipSize / 2.0
        require(halfSpread.isFinite() && halfSpread >= 0.0) {
            "Invalid replay symbol spread"
        }
        val liquidationPrice = when (position.side) {
            PositionSide.BUY -> candle.close - halfSpread
            PositionSide.SELL -> candle.close + halfSpread
        }
        require(liquidationPrice.isFinite() && liquidationPrice > 0.0) {
            "Invalid replay liquidation price"
        }
        val grossPl = when (position.side) {
            PositionSide.BUY -> (liquidationPrice - position.entryPrice) * position.volume * symInfo.contractSize
            PositionSide.SELL -> (position.entryPrice - liquidationPrice) * position.volume * symInfo.contractSize
        }
        require(grossPl.isFinite()) { "Invalid replay floating P&L" }

        return PositionEvaluation.KeepOpen(
            position.copy(currentPrice = liquidationPrice, profitLoss = grossPl)
        )
    }

    /**
     * Evaluates pending orders against a candle under conservative intrabar limits.
     */
    fun isPendingOrderTriggeredByCandle(order: Order, candle: Candle): Boolean {
        if (order.status != OrderStatus.PENDING ||
            !order.symbol.equals(candle.symbol, ignoreCase = true) ||
            !order.requestedPrice.isFinite() || order.requestedPrice <= 0.0 ||
            !order.volume.isFinite() || order.volume <= 0.0 ||
            !candle.low.isFinite() || !candle.high.isFinite() ||
            !candle.open.isFinite() || !candle.close.isFinite() ||
            candle.low <= 0.0 || candle.high < candle.low ||
            candle.open !in candle.low..candle.high ||
            candle.close !in candle.low..candle.high) return false
        return when (order.type) {
            OrderType.BUY_LIMIT -> order.direction == OrderSide.BUY && candle.low <= order.requestedPrice
            OrderType.SELL_LIMIT -> order.direction == OrderSide.SELL && candle.high >= order.requestedPrice
            OrderType.BUY_STOP -> order.direction == OrderSide.BUY && candle.high >= order.requestedPrice
            OrderType.SELL_STOP -> order.direction == OrderSide.SELL && candle.low <= order.requestedPrice
            OrderType.LIMIT -> if (order.direction == OrderSide.BUY) candle.low <= order.requestedPrice else candle.high >= order.requestedPrice
            OrderType.STOP -> if (order.direction == OrderSide.BUY) candle.high >= order.requestedPrice else candle.low <= order.requestedPrice
            else -> false
        }
    }

    private fun updateVisibleState(evaluateTrades: Boolean = true) {
        val idx = _currentIndex.value
        if (idx in allCandles.indices) {
            val active = allCandles[idx]

            // Strictly guard against lookahead bias: reveal ONLY up to active.openTime
            val visible = DataIntegrityValidator.enforceReplayBarrier(
                allCandles.subList(0, idx + 1),
                active.openTime
            )
            _visibleCandles.value = visible
            _currentCandle.value = active
            replayClock.updateCurrentTime(active.openTime)

            // Authentic symbol spread calculation labeled REPLAY_DATA
            val symInfo = DefaultSymbols.getSymbol(active.symbol)
            val spread = symInfo.defaultSpreadPips * symInfo.pipSize
            val halfSpread = spread / 2.0

            val tick = Tick(
                symbol = active.symbol,
                bid = active.close - halfSpread,
                ask = active.close + halfSpread,
                last = active.close,
                timestamp = active.openTime + (active.timeframe.minutes * 60000L),
                source = "REPLAY_DATA",
                volume = active.volume
            )
            _currentTick.value = tick

            if (evaluateTrades) {
                val dataView = ReplayDataView(allCandles, idx, tick)
                onCandleRevealed?.invoke(active, tick, dataView)
            }
        }
    }
}
