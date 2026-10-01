package com.example.feature.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.model.ExitReason
import com.example.core.model.PositionSide
import com.example.core.model.TradeJournalEntry
import com.example.data.repository.TradingRepository
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

enum class HistoryTab(val displayNameAr: String) {
    ALL("الكل"),
    WIN("رابحة"),
    LOSS("خاسرة"),
    BUY("شراء"),
    SELL("بيع"),
    SL("وقف خسارة"),
    TP("هدف ربحي"),
    MANUAL("إغلاق يدوي"),
    STRATEGY("استراتيجية")
}

data class HistoryUiState(
    val trades: List<TradeJournalEntry> = emptyList(),
    val totalTradesCount: Int = 0,
    val selectedTab: HistoryTab = HistoryTab.ALL,
    val filterSymbol: String? = null,
    val totalNetProfit: Double = 0.0,
    val winRatePct: Double = 0.0,
    val isLoading: Boolean = false
)

class HistoryViewModel(
    private val tradingRepository: TradingRepository
) : ViewModel() {

    private val allTradesFlow = MutableStateFlow<List<TradeJournalEntry>>(emptyList())
    private val _selectedTab = MutableStateFlow(HistoryTab.ALL)
    private val _filterSymbol = MutableStateFlow<String?>(null)

    val uiState: StateFlow<HistoryUiState> = combine(
        allTradesFlow,
        _selectedTab,
        _filterSymbol
    ) { trades, tab, sym ->
        val filtered = trades.filter { t ->
            val matchSym = sym == null || t.symbol == sym
            val matchTab = when (tab) {
                HistoryTab.ALL -> true
                HistoryTab.WIN -> t.netProfitLoss > 0
                HistoryTab.LOSS -> t.netProfitLoss < 0
                HistoryTab.BUY -> t.side == PositionSide.BUY
                HistoryTab.SELL -> t.side == PositionSide.SELL
                HistoryTab.SL -> t.exitReason == ExitReason.STOP_LOSS
                HistoryTab.TP -> t.exitReason == ExitReason.TAKE_PROFIT
                HistoryTab.MANUAL -> t.exitReason == ExitReason.MANUAL_CLOSE
                HistoryTab.STRATEGY -> t.exitReason == ExitReason.STRATEGY_CLOSE || t.strategyId != null
            }
            matchSym && matchTab
        }

        val totalNet = filtered.sumOf { it.netProfitLoss }
        val wins = filtered.count { it.isWin }
        val winRate = if (filtered.isNotEmpty()) (wins.toDouble() / filtered.size) * 100.0 else 0.0

        HistoryUiState(
            trades = filtered,
            totalTradesCount = filtered.size,
            selectedTab = tab,
            filterSymbol = sym,
            totalNetProfit = totalNet,
            winRatePct = winRate
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), HistoryUiState())

    init {
        viewModelScope.launch {
            tradingRepository.selectedAccount.filterNotNull().flatMapLatest { acc ->
                tradingRepository.getTradesForAccount(acc.id)
            }.collect { trades ->
                allTradesFlow.value = trades
            }
        }
    }

    fun selectTab(tab: HistoryTab) {
        _selectedTab.value = tab
    }

    fun filterBySymbol(symbol: String?) {
        _filterSymbol.value = symbol
    }
}
