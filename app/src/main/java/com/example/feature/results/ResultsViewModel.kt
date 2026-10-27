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
    STATISTICS("إحصائيات الصفقات"),
    DAILY("النتائج اليومية"),
    COMPARISON("مقارنة الاختبارات")
}

data class ResultsUiState(
    val analytics: TrainingAnalytics? = null,
    val customStart:Long?=null,
    val customEnd:Long?=null,
    val isReplayReport: Boolean = false,
    val openPositionsCount: Int = 0,
    val openPositions: List<Position> = emptyList(),
    val initialBalance: Double = 100.0,
    val currentBalance: Double = 100.0,
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
    private val tradingRepository: TradingRepository,
    private val trainingStore:com.example.feature.replay.TrainingSessionStore?=null
) : ViewModel() {

    private val _uiState = MutableStateFlow(ResultsUiState(isLoading = true))
    private val reports=trainingStore?.observeReports() ?: tradingRepository.replayReport
    val uiState: StateFlow<ResultsUiState> = combine(_uiState, reports) { base, report ->
        if(report==null) base.copy(isReplayReport=true,isLoading=false) else {
            val analytics=TrainingAnalyticsCalculator.calculate(report,base.selectedPeriod,customStart=base.customStart,customEnd=base.customEnd)
            base.copy(analytics=analytics,isReplayReport=true,openPositionsCount=report.positions.size,openPositions=report.positions,
                initialBalance=analytics.opening,currentBalance=analytics.closing,metrics=analytics.metrics,equityPoints=analytics.curve,
                trades=analytics.trades,dailySummaries=analytics.days.map { day-> val f=java.text.SimpleDateFormat("yyyy-MM-dd",java.util.Locale.US);DailySummary(java.text.SimpleDateFormat("dd/MM",java.util.Locale.US).format(java.util.Date(day.time)),f.format(java.util.Date(day.time)),day.pnl,day.count,analytics.trades.filterIndexed { i,_ -> TrainingAnalyticsCalculator.dayStart(analytics.recordedAt[i])==day.time }.sumOf { it.volume },if(day.count>0)day.wins*100.0/day.count else 0.0) },isLoading=false)
        }
    }.flowOn(kotlinx.coroutines.Dispatchers.Default).stateIn(viewModelScope,SharingStarted.WhileSubscribed(5000),ResultsUiState(isLoading=true))

    fun setCustomRange(start:Long,end:Long) { if(start<=end)_uiState.update { it.copy(selectedPeriod=ResultsPeriod.CUSTOM,customStart=start,customEnd=end) } }

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
