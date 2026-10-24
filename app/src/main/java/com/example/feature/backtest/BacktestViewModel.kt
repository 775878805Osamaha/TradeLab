package com.example.feature.backtest

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.backtest.BacktestConfig
import com.example.core.backtest.BacktestEngine
import com.example.core.backtest.BacktestProgressStage
import com.example.core.backtest.BacktestResult
import com.example.core.model.BacktestRun
import com.example.core.model.PositionSizingMode
import com.example.core.model.Timeframe
import com.example.core.strategy.Strategy
import com.example.core.strategy.StrategyRegistry
import com.example.data.repository.MarketDataRepository
import com.example.data.repository.TradingRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class ResultsDisplayMode {
    VALUE,
    PERCENTAGE
}

enum class BacktestTab {
    CONFIG,
    RESULTS,
    HISTORY
}

data class BacktestUiState(
    val availableStrategies: List<Strategy> = StrategyRegistry.AVAILABLE_STRATEGIES,
    val selectedStrategy: Strategy? = StrategyRegistry.AVAILABLE_STRATEGIES.firstOrNull(),
    val symbol: String = "XAUUSD",
    val timeframe: Timeframe = Timeframe.M15,
    val initialBalance: String = "50.0",
    val positionSizingMode: PositionSizingMode = PositionSizingMode.FIXED_LOT,
    val riskPercentage: String = "1.0",
    val fixedLotSize: String = "0.01",
    val fixedRiskAmount: String = "5.0",
    val leverage: String = "100.0",
    val spreadPips: String = "1.5",
    val commission: String = "5.0",
    val slippage: String = "0.2",
    val swap: String = "1.0",
    val allowMultiplePositions: Boolean = false,
    val allowLong: Boolean = true,
    val allowShort: Boolean = true,
    val isRunning: Boolean = false,
    val currentStage: BacktestProgressStage? = null,
    val progressFraction: Float = 0f,
    val lastResult: BacktestResult? = null,
    val pastRuns: List<BacktestRun> = emptyList(),
    val selectedTab: BacktestTab = BacktestTab.CONFIG,
    val displayMode: ResultsDisplayMode = ResultsDisplayMode.VALUE,
    val message: String? = null
)

class BacktestViewModel(
    private val marketDataRepository: MarketDataRepository,
    private val backtestEngine: BacktestEngine = BacktestEngine(),
    private val tradingRepository: TradingRepository? = null
) : ViewModel() {

    private val _uiState = MutableStateFlow(BacktestUiState())
    val uiState: StateFlow<BacktestUiState> = _uiState.asStateFlow()

    private var backtestJob: Job? = null

    init {
        // Collect past runs if repository provided
        tradingRepository?.let { repo ->
            viewModelScope.launch {
                repo.allBacktestRuns.collect { runs ->
                    _uiState.update { it.copy(pastRuns = runs) }
                }
            }
        }
    }

    fun selectStrategy(strategy: Strategy?) = _uiState.update { it.copy(selectedStrategy = strategy) }
    fun selectSymbol(symbol: String) = _uiState.update { it.copy(symbol = symbol) }
    fun selectTimeframe(tf: Timeframe) = _uiState.update { it.copy(timeframe = tf) }

    fun refreshAvailableStrategies() {
        val strats = StrategyRegistry.getAllStrategies()
        _uiState.update {
            it.copy(
                availableStrategies = strats,
                selectedStrategy = it.selectedStrategy?.let { sel -> strats.find { s -> s.id == sel.id } } ?: strats.firstOrNull()
            )
        }
    }

    fun setInitialBalance(b: String) = _uiState.update { it.copy(initialBalance = b) }
    fun setPositionSizingMode(mode: PositionSizingMode) = _uiState.update { it.copy(positionSizingMode = mode) }
    fun setRiskPercentage(r: String) = _uiState.update { it.copy(riskPercentage = r) }
    fun setFixedLotSize(l: String) = _uiState.update { it.copy(fixedLotSize = l) }
    fun setFixedRiskAmount(a: String) = _uiState.update { it.copy(fixedRiskAmount = a) }
    fun setLeverage(l: String) = _uiState.update { it.copy(leverage = l) }
    fun setSpreadPips(s: String) = _uiState.update { it.copy(spreadPips = s) }
    fun setCommission(c: String) = _uiState.update { it.copy(commission = c) }
    fun setSlippage(s: String) = _uiState.update { it.copy(slippage = s) }
    fun setSwap(sw: String) = _uiState.update { it.copy(swap = sw) }
    fun setAllowMultiplePositions(a: Boolean) = _uiState.update { it.copy(allowMultiplePositions = a) }
    fun setAllowLong(a: Boolean) = _uiState.update { it.copy(allowLong = a) }
    fun setAllowShort(a: Boolean) = _uiState.update { it.copy(allowShort = a) }
    fun setDisplayMode(mode: ResultsDisplayMode) = _uiState.update { it.copy(displayMode = mode) }
    fun setSelectedTab(tab: BacktestTab) = _uiState.update { it.copy(selectedTab = tab) }

    // Convenience method for backwards compatibility with tests
    fun setUseFixedLot(useFixed: Boolean) {
        _uiState.update {
            it.copy(
                positionSizingMode = if (useFixed) PositionSizingMode.FIXED_LOT else PositionSizingMode.RISK_PERCENTAGE
            )
        }
    }

    fun runBacktest() {
        val state = _uiState.value
        val strategy = state.selectedStrategy
        if (strategy == null) {
            _uiState.update { it.copy(message = "يرجى تحديد أو إنشاء استراتيجية لبدء الاختبار") }
            return
        }

        if (state.isRunning) return
        val config = try {
            BacktestConfig(
                strategy = strategy,
                symbol = state.symbol,
                timeframe = state.timeframe,
                initialBalance = parseBacktestNumber("رأس المال", state.initialBalance),
                leverage = parseBacktestNumber("الرافعة المالية", state.leverage),
                positionSizingMode = state.positionSizingMode,
                riskPercentage = parseBacktestNumber("نسبة المخاطرة", state.riskPercentage),
                fixedLot = parseBacktestNumber("حجم العقد", state.fixedLotSize),
                fixedRiskAmount = parseBacktestNumber("مبلغ المخاطرة", state.fixedRiskAmount),
                spreadPips = parseBacktestNumber("السبريد", state.spreadPips),
                slippagePips = parseBacktestNumber("الانزلاق", state.slippage),
                commissionPerLot = parseBacktestNumber("العمولة", state.commission),
                swapPerLotDaily = parseBacktestNumber("السواب", state.swap),
                allowMultiplePositions = state.allowMultiplePositions,
                allowLong = state.allowLong,
                allowShort = state.allowShort
            ).also { it.validate().getOrThrow() }
        } catch (error: IllegalArgumentException) {
            _uiState.update {
                it.copy(
                    isRunning = false,
                    currentStage = BacktestProgressStage.FAILED,
                    message = "إعدادات الاختبار غير صالحة: ${error.message}"
                )
            }
            return
        }

        _uiState.update {
            it.copy(
                isRunning = true,
                currentStage = BacktestProgressStage.PREPARING_DATA,
                progressFraction = 0.05f,
                lastResult = null,
                message = "بدء الاختبار التاريخي..."
            )
        }

        backtestJob?.cancel()
        backtestJob = viewModelScope.launch {
            try {
                val now = System.currentTimeMillis()
                val interval = state.timeframe.minutes * 60 * 1000L
                val from = now - (interval * 350)

                val sourceCandles = marketDataRepository.getCandles(state.symbol, state.timeframe, from, now)
                // The currently forming bar has unknown final OHLC. Never
                // allow it to enter historical strategy or execution logic.
                val candles = sourceCandles.filter { it.closeTime <= now }
                require(candles.isNotEmpty()) {
                    "لا توجد شموع تاريخية مكتملة للفترة المحددة"
                }

                val result = backtestEngine.runBacktest(candles, config) { stage, fraction ->
                    _uiState.update {
                        it.copy(
                            currentStage = stage,
                            progressFraction = fraction
                        )
                    }
                }

                // Save backtest run to database if repository available
                result.run?.let { run ->
                    tradingRepository?.saveBacktestRun(run)
                }

                _uiState.update {
                    it.copy(
                        isRunning = false,
                        currentStage = BacktestProgressStage.COMPLETED,
                        progressFraction = 1.0f,
                        lastResult = result,
                        selectedTab = BacktestTab.RESULTS,
                        message = "اكتمل الاختبار التاريخي: ${result.trades.size} صفقة منفذة بنجاح"
                    )
                }
            } catch (e: CancellationException) {
                _uiState.update {
                    it.copy(
                        isRunning = false,
                        currentStage = BacktestProgressStage.CANCELLED,
                        progressFraction = 0f,
                        message = "تم إلغاء الاختبار التاريخي بأمان دون التأثير على البيانات"
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isRunning = false,
                        currentStage = BacktestProgressStage.FAILED,
                        progressFraction = 0f,
                        lastResult = null,
                        message = "حدث خطأ أثناء الاختبار: ${e.message}"
                    )
                }
            }
        }
    }

    fun cancelBacktest() {
        if (_uiState.value.isRunning) {
            backtestJob?.cancel()
            backtestJob = null
            // Update synchronously: a cancelled run must not remain in a
            // running state if cancellation arrives before its first suspend.
            _uiState.update {
                it.copy(
                    isRunning = false,
                    currentStage = BacktestProgressStage.CANCELLED,
                    progressFraction = 0f,
                    lastResult = null,
                    message = "تم إلغاء الاختبار التاريخي"
                )
            }
        }
    }

    fun resetBacktest() {
        cancelBacktest()
        _uiState.update {
            it.copy(
                isRunning = false,
                lastResult = null,
                message = null,
                currentStage = null,
                progressFraction = 0f,
                selectedTab = BacktestTab.CONFIG
            )
        }
    }

    fun deleteRun(id: Long) {
        viewModelScope.launch {
            tradingRepository?.deleteBacktestRun(id)
        }
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }
}
