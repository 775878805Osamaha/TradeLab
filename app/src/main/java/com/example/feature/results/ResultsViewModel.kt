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
    private data class ReportSelection(val period:ResultsPeriod,val start:Long?,val end:Long?)
    private data class PreparedReport(val report:ReplayReport?,val analytics:TrainingAnalytics?,val days:List<DailySummary>)
    private val selection=_uiState.map { ReportSelection(it.selectedPeriod,it.customStart,it.customEnd) }.distinctUntilChanged()
    // Tab selection, detail dialogs and export visibility never invalidate account calculations.
    private val prepared=combine(reports,selection) { report,range ->
        if(report==null) PreparedReport(null,null,emptyList()) else {
            val a=TrainingAnalyticsCalculator.calculate(report,range.period,customStart=range.start,customEnd=range.end)
            val volumeByDay=a.trades.indices.groupBy { TrainingAnalyticsCalculator.dayStart(a.recordedAt[it]) }
                .mapValues { (_,indices)->indices.sumOf { a.trades[it].volume } }
            val keyFormat=java.text.SimpleDateFormat("yyyy-MM-dd",java.util.Locale.US)
            val labelFormat=java.text.SimpleDateFormat("dd/MM",java.util.Locale.US)
            val daily=a.days.map { day->
                val date=java.util.Date(day.time)
                DailySummary(labelFormat.format(date),keyFormat.format(date),day.pnl,day.count,
                    volumeByDay[day.time]?:0.0,if(day.count>0)day.wins*100.0/day.count else 0.0)
            }
            PreparedReport(report,a,daily)
        }
    }.flowOn(kotlinx.coroutines.Dispatchers.Default)
    val uiState: StateFlow<ResultsUiState> = combine(_uiState,prepared) { base,prepared ->
        val report=prepared.report
        val a=prepared.analytics
        if(report==null || a==null) base.copy(
            analytics=null,isReplayReport=true,openPositionsCount=0,openPositions=emptyList(),
            metrics=null,equityPoints=emptyList(),trades=emptyList(),dailySummaries=emptyList(),
            initialBalance=100.0,currentBalance=100.0,selectedTradeForDetail=null,isLoading=false
        ) else
            base.copy(analytics=a,isReplayReport=true,openPositionsCount=report.positions.size,openPositions=report.positions,
                initialBalance=a.opening,currentBalance=a.closing,metrics=a.metrics,equityPoints=a.curve,
                trades=a.trades,dailySummaries=prepared.days,
                // A previously opened trade detail must not show a trade that
                // disappeared after Replay rewind, account reset or filtering.
                selectedTradeForDetail=base.selectedTradeForDetail?.takeIf { selected ->
                    a.trades.any { it == selected }
                },isLoading=false)
    }.stateIn(viewModelScope,SharingStarted.WhileSubscribed(5000),ResultsUiState(isLoading=true))

    fun setCustomRange(start:Long,end:Long) { if(start<=end && start<=System.currentTimeMillis())_uiState.update { it.copy(selectedPeriod=ResultsPeriod.CUSTOM,customStart=start,customEnd=end) } }

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
