package com.example.feature.results

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.model.*
import com.example.core.statistics.StatisticsCalculator
import com.example.data.repository.TradingRepository
import com.example.ui.components.ChartCurveType
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

enum class ResultsTab(val displayNameAr: String) {
    OVERVIEW("نظرة عامة"),
    CURVES("المنحنيات البيانية"),
    JOURNAL("يوميات الصفقات"),
    DAILY("النتائج اليومية"),
    COMPARISON("مقارنة الاختبارات")
}

data class ResultsUiState(
    val isReplayReport: Boolean = false,
    val openPositionsCount: Int = 0,
    val openPositions: List<Position> = emptyList(),
    val initialBalance: Double = 50.0,
    val currentBalance: Double = 50.0,
    val metrics: PerformanceMetrics? = null,
    val equityPoints: List<EquityPoint> = emptyList(),
    val trades: List<TradeJournalEntry> = emptyList(),
    val dailySummaries: List<DailySummary> = emptyList(),
    val pastRuns: List<BacktestRun> = emptyList(),
    val selectedRunsForComparison: Set<Long> = emptySet(),
    val selectedTab: ResultsTab = ResultsTab.OVERVIEW,
    val selectedPeriod: ResultsPeriod = ResultsPeriod.ALL,
    val curveType: ChartCurveType = ChartCurveType.EQUITY_AND_BALANCE,
    val isPercentageMode: Boolean = false,
    val selectedTradeForDetail: TradeJournalEntry? = null,
    val isExportDialogOpen: Boolean = false,
    val isLoading: Boolean = false
)

class ResultsViewModel(
    private val tradingRepository: TradingRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(ResultsUiState(isLoading = true))
    val uiState: StateFlow<ResultsUiState> = combine(_uiState, tradingRepository.replayReport) { base, report ->
        if (report == null) base.copy(isReplayReport=true,isLoading=false) else base.copy(
            isReplayReport=true,openPositionsCount=report.positions.size,openPositions=report.positions,
            initialBalance=report.account.initialBalance,currentBalance=report.account.balance,
            metrics=StatisticsCalculator.calculate(report.account.initialBalance,report.trades,report.account.equity).copy(maxDrawdown=report.maxDrawdown,maxDrawdownPct=report.maxDrawdownPercent),
            equityPoints=report.curve.ifEmpty { StatisticsCalculator.buildEquityCurve(report.account.initialBalance,report.trades) },
            trades=report.trades,dailySummaries=StatisticsCalculator.calculateDailySummaries(report.trades),isLoading=false)
    }.stateIn(viewModelScope,SharingStarted.WhileSubscribed(5000),ResultsUiState(isLoading=true))

    fun setSelectedPeriod(period: ResultsPeriod) {
        _uiState.update { it.copy(selectedPeriod = period) }
    }

    fun togglePercentageMode() {
        _uiState.update { it.copy(isPercentageMode = !it.isPercentageMode) }
    }

    fun setCurveType(type: ChartCurveType) {
        _uiState.update { it.copy(curveType = type) }
    }

    fun setSelectedTab(tab: ResultsTab) {
        _uiState.update { it.copy(selectedTab = tab) }
    }

    fun selectTradeForDetail(trade: TradeJournalEntry?) {
        _uiState.update { it.copy(selectedTradeForDetail = trade) }
    }

    fun setExportDialogOpen(open: Boolean) {
        _uiState.update { it.copy(isExportDialogOpen = open) }
    }

    fun toggleRunComparison(runId: Long) {
        _uiState.update {
            val current = it.selectedRunsForComparison.toMutableSet()
            if (current.contains(runId)) current.remove(runId) else current.add(runId)
            it.copy(selectedRunsForComparison = current)
        }
    }

    fun clearComparisonSelection() {
        _uiState.update { it.copy(selectedRunsForComparison = emptySet()) }
    }
}
