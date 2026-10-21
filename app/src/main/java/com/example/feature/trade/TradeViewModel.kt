package com.example.feature.trade

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.execution.OrderValidationResult
import com.example.core.execution.OrderValidator
import com.example.core.market.DefaultSymbols
import com.example.core.model.*
import com.example.core.risk.RiskEngine
import com.example.data.repository.MarketDataRepository
import com.example.data.repository.TradingRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

enum class RiskCalculationMode(val displayNameAr: String) {
    FIXED_LOT("حجم ثابت (Fixed Lot)"),
    RISK_PERCENTAGE("نسبة مئوية (Risk %)"),
    MONETARY_RISK("مبلغ مالي (Cash Risk)")
}

data class TradeUiState(
    val selectedAccount: VirtualAccount? = null,
    val openPositions: List<Position> = emptyList(),
    val pendingOrders: List<Order> = emptyList(),
    val selectedSymbol: String = "BTCUSDT",
    val orderType: OrderType = OrderType.MARKET,
    val orderSide: OrderSide = OrderSide.BUY,
    val volume: String = "0.01",
    val requestedPrice: String = "",
    val stopLoss: String = "",
    val takeProfit: String = "",
    val trailingDistancePips: String = "",
    val latestTick: Tick? = null,
    val candles: List<Candle> = emptyList(),
    val riskAnalysis: RiskAnalysis? = null,
    val riskMode: RiskCalculationMode = RiskCalculationMode.FIXED_LOT,
    val riskPercentageInput: String = "1.0",
    val monetaryRiskInput: String = "2.0",
    val oneTapTradingEnabled: Boolean = false,
    val isOrderPreviewVisible: Boolean = false,
    val selectedPositionForDetail: Position? = null,
    val isEmaEnabled: Boolean = true,
    val message: String? = null,
    val isLoading: Boolean = false,
    val isSubmittingOrder: Boolean = false
)

class TradeViewModel(
    private val tradingRepository: TradingRepository,
    private val marketDataRepository: MarketDataRepository,
    private val riskEngine: RiskEngine = RiskEngine()
) : ViewModel() {

    private val _uiState = MutableStateFlow(TradeUiState())
    val uiState: StateFlow<TradeUiState> = _uiState.asStateFlow()

    private var tickJob: Job? = null
    private var candleLoadJob: Job? = null
    private var lastOrderExecutionTime = 0L

    init {
        observeAccountAndPositions()
        selectSymbol(_uiState.value.selectedSymbol)
    }

    private fun observeAccountAndPositions() {
        viewModelScope.launch {
            tradingRepository.selectedAccount.collect { account ->
                _uiState.update { it.copy(selectedAccount = account) }
                if (account != null) {
                    launch {
                        tradingRepository.getPositionsForAccount(account.id).collect { positions ->
                            _uiState.update { it.copy(openPositions = positions) }
                            recalculateRisk()
                        }
                    }
                    launch {
                        tradingRepository.getPendingOrdersForAccount(account.id).collect { pending ->
                            _uiState.update { it.copy(pendingOrders = pending) }
                        }
                    }
                }
            }
        }
    }

    fun selectSymbol(symbol: String) {
        val symInfo = DefaultSymbols.getSymbol(symbol)
        _uiState.update {
            it.copy(
                selectedSymbol = symInfo.symbol, volume = symInfo.minLot.toString(),
                latestTick = null, candles = emptyList(), riskAnalysis = null,
                message = null, isOrderPreviewVisible = false
            )
        }
        subscribeToSymbolTicks(symInfo.symbol)
        loadCandles(symInfo.symbol)
        recalculateRisk()
    }

    fun setOrderSide(side: OrderSide) {
        _uiState.update { it.copy(orderSide = side) }
        recalculateRisk()
    }

    fun setOrderType(type: OrderType) {
        _uiState.update { it.copy(orderType = type) }
        recalculateRisk()
    }

    fun setVolume(vol: String) {
        _uiState.update { it.copy(volume = vol, riskMode = RiskCalculationMode.FIXED_LOT) }
        recalculateRisk()
    }

    fun adjustVolume(delta: Double) {
        val current = _uiState.value.volume.toDoubleOrNull() ?: 0.01
        val symInfo = DefaultSymbols.getSymbol(_uiState.value.selectedSymbol)
        val newVol = ((current + delta) / symInfo.lotStep).toInt() * symInfo.lotStep
        val clamped = newVol.coerceIn(symInfo.minLot, symInfo.maxLot)
        _uiState.update { it.copy(volume = String.format("%.2f", clamped), riskMode = RiskCalculationMode.FIXED_LOT) }
        recalculateRisk()
    }

    fun setRequestedPrice(price: String) {
        _uiState.update { it.copy(requestedPrice = price) }
        recalculateRisk()
    }

    fun setStopLoss(sl: String) {
        _uiState.update { it.copy(stopLoss = sl) }
        applyRiskModeLot()
        recalculateRisk()
    }

    fun setTakeProfit(tp: String) {
        _uiState.update { it.copy(takeProfit = tp) }
        recalculateRisk()
    }

    fun setRiskMode(mode: RiskCalculationMode) {
        _uiState.update { it.copy(riskMode = mode) }
        applyRiskModeLot()
        recalculateRisk()
    }

    fun setRiskPercentage(pctStr: String) {
        _uiState.update { it.copy(riskPercentageInput = pctStr, riskMode = RiskCalculationMode.RISK_PERCENTAGE) }
        applyRiskModeLot()
        recalculateRisk()
    }

    fun setMonetaryRisk(cashStr: String) {
        _uiState.update { it.copy(monetaryRiskInput = cashStr, riskMode = RiskCalculationMode.MONETARY_RISK) }
        applyRiskModeLot()
        recalculateRisk()
    }

    fun toggleOneTapTrading() {
        val next = !_uiState.value.oneTapTradingEnabled
        _uiState.update { it.copy(oneTapTradingEnabled = next) }
    }

    fun setOrderPreviewVisible(visible: Boolean) {
        _uiState.update { it.copy(isOrderPreviewVisible = visible) }
    }

    fun selectPositionForDetail(position: Position?) {
        _uiState.update { it.copy(selectedPositionForDetail = position) }
    }

    private fun applyRiskModeLot() {
        val state = _uiState.value
        val account = state.selectedAccount ?: return
        val tick = state.latestTick ?: return
        val sl = state.stopLoss.toDoubleOrNull() ?: return
        val symInfo = DefaultSymbols.getSymbol(state.selectedSymbol)
        val entry = if (state.orderSide == OrderSide.BUY) tick.ask else tick.bid
        val pips = kotlin.math.abs(entry - sl) / symInfo.pipSize

        if (pips <= 0.0) return

        when (state.riskMode) {
            RiskCalculationMode.RISK_PERCENTAGE -> {
                val pct = state.riskPercentageInput.toDoubleOrNull() ?: 1.0
                val lot = riskEngine.calculateSuggestedLot(account, state.selectedSymbol, pct, pips)
                _uiState.update { it.copy(volume = String.format("%.2f", lot)) }
            }
            RiskCalculationMode.MONETARY_RISK -> {
                val cash = state.monetaryRiskInput.toDoubleOrNull() ?: 2.0
                val pct = if (account.balance > 0) (cash / account.balance) * 100.0 else 1.0
                val lot = riskEngine.calculateSuggestedLot(account, state.selectedSymbol, pct, pips)
                _uiState.update { it.copy(volume = String.format("%.2f", lot)) }
            }
            RiskCalculationMode.FIXED_LOT -> {}
        }
    }

    private fun recalculateRisk() {
        val state = _uiState.value
        val account = state.selectedAccount ?: return
        val tick = state.latestTick ?: return
        val vol = state.volume.toDoubleOrNull() ?: 0.01
        val sl = state.stopLoss.toDoubleOrNull()
        val tp = state.takeProfit.toDoubleOrNull()
        val entry = if (state.orderSide == OrderSide.BUY) tick.ask else tick.bid

        val analysis = riskEngine.analyzeRisk(
            account = account,
            symbol = state.selectedSymbol,
            side = state.orderSide,
            volume = vol,
            entryPrice = entry,
            stopLoss = sl,
            takeProfit = tp
        )
        _uiState.update { it.copy(riskAnalysis = analysis) }
    }

    /**
     * Places a virtual order (Market or Pending) with click debouncing, stale check, and validation.
     */
    fun placeOrder(sideOverride: OrderSide? = null) {
        val now = System.currentTimeMillis()
        if (now - lastOrderExecutionTime < 400L) {
            return
        }
        lastOrderExecutionTime = now

        val state = _uiState.value
        val effectiveSide = sideOverride ?: state.orderSide
        val account = state.selectedAccount ?: run {
            _uiState.update { it.copy(message = "لم يتم تحديد حساب افتراضي") }
            return
        }

        // Stale Market Data Protection
        val isStale = marketDataRepository.provider.dataSourceType.value == DataSourceType.STALE_DATA
        val isDisconnected = marketDataRepository.provider.connectionStatus.value == ProviderConnectionStatus.DISCONNECTED
        if (state.orderType == OrderType.MARKET && (isStale || isDisconnected)) {
            _uiState.update { it.copy(message = "بيانات السوق متأخرة أو غير متصلة (STALE DATA). تم إيقاف التنفيذ لحماية الحساب الافتراضي.") }
            return
        }

        // Never submit a virtual market order using an old or unsupported quote.
        val verifiedMarketQuote = state.latestTick?.let { quote ->
            quote.symbol == state.selectedSymbol &&
                quote.source in setOf("BINANCE_WEBSOCKET", "BINANCE_REST_POLL") &&
                System.currentTimeMillis() - quote.timestamp in 0..15_000L
        } == true
        if (state.orderType == OrderType.MARKET && !verifiedMarketQuote) {
            _uiState.update { it.copy(message = "السعر المباشر غير متاح أو متأخر. انتظر تحديث Binance قبل تنفيذ الأمر.") }
            return
        }

        val tick = state.latestTick ?: run {
            _uiState.update { it.copy(message = "بيانات السوق غير متصلة حالياً") }
            return
        }

        val vol = state.volume.toDoubleOrNull() ?: 0.01
        val sl = state.stopLoss.toDoubleOrNull()
        val tp = state.takeProfit.toDoubleOrNull()

        viewModelScope.launch {
            _uiState.update { it.copy(isSubmittingOrder = true, isOrderPreviewVisible = false) }

            if (state.orderType == OrderType.MARKET) {
                val result = tradingRepository.executeMarketOrder(
                    accountId = account.id,
                    symbol = state.selectedSymbol,
                    side = effectiveSide,
                    volume = vol,
                    tick = tick,
                    stopLoss = sl,
                    takeProfit = tp
                )

                result.onSuccess {
                    _uiState.update {
                        it.copy(
                            message = "VIRTUAL ORDER FILLED: تم فتح أمر ${effectiveSide.displayNameAr} $vol لوت بنجاح",
                            stopLoss = "",
                            takeProfit = "",
                            isSubmittingOrder = false
                        )
                    }
                }.onFailure { err ->
                    _uiState.update {
                        it.copy(message = err.message ?: "فشل تنفيذ الأمر", isSubmittingOrder = false)
                    }
                }
            } else {
                // Pending Order
                val reqPrice = state.requestedPrice.toDoubleOrNull() ?: run {
                    _uiState.update { it.copy(message = "يرجى تحديد السعر المستهدف للأمر المعلق", isSubmittingOrder = false) }
                    return@launch
                }

                val result = tradingRepository.placePendingOrder(
                    accountId = account.id,
                    symbol = state.selectedSymbol,
                    type = state.orderType,
                    side = effectiveSide,
                    volume = vol,
                    requestedPrice = reqPrice,
                    stopLoss = sl,
                    takeProfit = tp,
                    tick = tick
                )

                result.onSuccess {
                    _uiState.update {
                        it.copy(
                            message = "VIRTUAL PENDING PLACED: تم إدراج الأمر المعلق بنجاح عند سعر $reqPrice",
                            requestedPrice = "",
                            stopLoss = "",
                            takeProfit = "",
                            isSubmittingOrder = false
                        )
                    }
                }.onFailure { err ->
                    _uiState.update {
                        it.copy(message = err.message ?: "فشل إدراج الأمر المعلق", isSubmittingOrder = false)
                    }
                }
            }
        }
    }

    fun cancelPendingOrder(orderId: Long) {
        viewModelScope.launch {
            tradingRepository.cancelPendingOrder(orderId)
            _uiState.update { it.copy(message = "تم إلغاء الأمر المعلق بنجاح") }
        }
    }

    fun closePosition(positionId: Long) {
        val pos = _uiState.value.openPositions.firstOrNull { it.id == positionId } ?: return
        val tick = _uiState.value.latestTick
        val exitPrice = if (pos.side == PositionSide.BUY) (tick?.bid ?: pos.currentPrice) else (tick?.ask ?: pos.currentPrice)

        viewModelScope.launch {
            tradingRepository.closePosition(pos.id, exitPrice, ExitReason.MANUAL_CLOSE)
            _uiState.update { it.copy(message = "تم إغلاق الصفقة بنجاح", selectedPositionForDetail = null) }
        }
    }

    fun partialClosePosition(positionId: Long, volume: Double) {
        val pos = _uiState.value.openPositions.firstOrNull { it.id == positionId } ?: return
        val tick = _uiState.value.latestTick
        val exitPrice = if (pos.side == PositionSide.BUY) (tick?.bid ?: pos.currentPrice) else (tick?.ask ?: pos.currentPrice)

        viewModelScope.launch {
            tradingRepository.closePosition(pos.id, exitPrice, ExitReason.MANUAL_CLOSE, partialVolume = volume)
            _uiState.update { it.copy(message = "تم الإغلاق الجزئي لـ $volume لوت بنجاح", selectedPositionForDetail = null) }
        }
    }

    fun setBreakEven(positionId: Long, protectionOffsetPips: Double = 1.0) {
        viewModelScope.launch {
            val result = tradingRepository.setBreakEven(positionId, protectionOffsetPips)
            result.onSuccess { bePrice ->
                _uiState.update { it.copy(message = "تم نقل وقف الخسارة إلى نقطة التعادل ($bePrice) بنجاح", selectedPositionForDetail = null) }
            }.onFailure { err ->
                _uiState.update { it.copy(message = err.message ?: "فشل تفعيل نقطة التعادل") }
            }
        }
    }

    fun setTrailingStop(positionId: Long, distancePips: Double) {
        viewModelScope.launch {
            tradingRepository.setTrailingStop(positionId, distancePips)
            _uiState.update { it.copy(message = "تم ضبط الوقف المتحرك بمقدار $distancePips نقطة") }
        }
    }

    fun modifyPosition(positionId: Long, sl: Double?, tp: Double?) {
        viewModelScope.launch {
            tradingRepository.modifyPosition(positionId, sl, tp)
            _uiState.update { it.copy(message = "تم تعديل مستويات الصفقة بنجاح", selectedPositionForDetail = null) }
        }
    }

    private fun loadCandles(symbol: String) {
        candleLoadJob?.cancel()
        candleLoadJob = viewModelScope.launch {
            val result = loadTradeCandles(symbol) {
                val now = System.currentTimeMillis()
                marketDataRepository.getCandles(symbol, Timeframe.M15, now - 86_400_000L, now)
            }
            _uiState.update { state ->
                if (state.selectedSymbol == symbol) {
                    state.copy(candles = result.candles, message = result.message)
                } else state
            }
        }
    }

    private fun subscribeToSymbolTicks(symbol: String) {
        tickJob?.cancel()
        tickJob = viewModelScope.launch {
            marketDataRepository.observeTicks(symbol).collect { tick ->
                if (_uiState.value.selectedSymbol != symbol || tick.symbol != symbol) return@collect
                _uiState.update { it.copy(latestTick = tick) }
                tradingRepository.onTickUpdate(tick)
                recalculateRisk()
            }
        }
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }
}
