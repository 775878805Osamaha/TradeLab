package com.example.feature.calendar

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.model.DailySummary
import com.example.core.model.TradeJournalEntry
import com.example.data.repository.TradingRepository
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

data class CalendarUiState(
    val dailySummaries: List<DailySummary> = emptyList(),
    val tradesByDate: Map<String, List<TradeJournalEntry>> = emptyMap(),
    val selectedDate: String? = null,
    val selectedDateTrades: List<TradeJournalEntry> = emptyList()
)

class TradingCalendarViewModel(
    private val tradingRepository: TradingRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(CalendarUiState())
    val uiState: StateFlow<CalendarUiState> = _uiState.asStateFlow()

    init {
        val sdfShort = SimpleDateFormat("dd/MM", Locale.US)
        val sdfFull = SimpleDateFormat("yyyy-MM-dd", Locale.US)

        viewModelScope.launch {
            tradingRepository.selectedAccount.filterNotNull().flatMapLatest { acc ->
                tradingRepository.getTradesForAccount(acc.id)
            }.collect { trades ->
                val grouped = trades.groupBy { sdfFull.format(Date(it.closeTime)) }

                val summaries = grouped.map { (dateKey, dayTrades) ->
                    val pl = dayTrades.sumOf { it.netProfitLoss }
                    val lots = dayTrades.sumOf { it.volume }
                    val wins = dayTrades.count { it.netProfitLoss > 0 }
                    val wr = if (dayTrades.isNotEmpty()) (wins.toDouble() / dayTrades.size) * 100.0 else 0.0
                    val shortDate = if (dayTrades.isNotEmpty()) sdfShort.format(Date(dayTrades.first().closeTime)) else dateKey

                    DailySummary(
                        dateStr = shortDate,
                        fullDate = dateKey,
                        profitLoss = pl,
                        tradeCount = dayTrades.size,
                        totalLots = lots,
                        winRatePct = wr
                    )
                }.sortedByDescending { it.fullDate }

                _uiState.update {
                    it.copy(
                        dailySummaries = summaries,
                        tradesByDate = grouped
                    )
                }
            }
        }
    }

    fun selectDate(dateKey: String) {
        val trades = _uiState.value.tradesByDate[dateKey] ?: emptyList()
        _uiState.update {
            it.copy(selectedDate = dateKey, selectedDateTrades = trades)
        }
    }

    fun clearSelectedDate() {
        _uiState.update {
            it.copy(selectedDate = null, selectedDateTrades = emptyList())
        }
    }
}
