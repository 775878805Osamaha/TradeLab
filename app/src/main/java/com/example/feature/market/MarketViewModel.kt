package com.example.feature.market

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.model.DataSourceType
import com.example.core.model.ProviderConnectionStatus
import com.example.core.model.SymbolInfo
import com.example.core.model.Tick
import com.example.data.repository.MarketDataRepository
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

enum class MarketSort {
    SYMBOL,
    SPREAD,
    CHANGE_PCT
}

data class SymbolMarketRow(
    val symbolInfo: SymbolInfo,
    val tick: Tick?,
    val dailyChangePct: Double? = null
) {
    val spreadPips: Double
        get() = if (tick != null) tick.spread / symbolInfo.pipSize else symbolInfo.defaultSpreadPips
}

data class MarketUiState(
    val rows: List<SymbolMarketRow> = emptyList(),
    val searchQuery: String = "",
    val showOnlyFavorites: Boolean = false,
    val sortOption: MarketSort = MarketSort.SYMBOL,
    val connectionStatus: ProviderConnectionStatus = ProviderConnectionStatus.DISCONNECTED,
    val dataSourceType: DataSourceType = DataSourceType.STALE_DATA,
    val isLoading: Boolean = false
)

class MarketViewModel(
    private val marketDataRepository: MarketDataRepository
) : ViewModel() {

    private val _searchQuery = MutableStateFlow("")
    private val _showOnlyFavorites = MutableStateFlow(false)
    private val _sortOption = MutableStateFlow(MarketSort.SYMBOL)
    private val ticksMap = MutableStateFlow<Map<String, Tick>>(emptyMap())
    private val symbolTickJobs = mutableMapOf<String, Job>()

    val uiState: StateFlow<MarketUiState> = combine(
        marketDataRepository.symbols,
        ticksMap,
        _searchQuery,
        _showOnlyFavorites,
        _sortOption,
        marketDataRepository.provider.connectionStatus,
        marketDataRepository.provider.dataSourceType
    ) { args: Array<Any?> ->
        @Suppress("UNCHECKED_CAST")
        val symbols = args[0] as List<SymbolInfo>
        @Suppress("UNCHECKED_CAST")
        val ticks = args[1] as Map<String, Tick>
        val query = args[2] as String
        val onlyFavs = args[3] as Boolean
        val sort = args[4] as MarketSort
        val connStatus = args[5] as ProviderConnectionStatus
        val dsType = args[6] as DataSourceType

        val filtered = symbols.filter { sym ->
            val matchesQuery = query.isBlank() || sym.symbol.contains(query, ignoreCase = true) || sym.name.contains(query, ignoreCase = true)
            val matchesFav = !onlyFavs || sym.isFavorite
            matchesQuery && matchesFav
        }.map { sym ->
            val tick = ticks[sym.symbol]
            SymbolMarketRow(
                symbolInfo = sym,
                tick = tick,
                dailyChangePct = null // No real 24h change feed: never fabricate market performance
            )
        }.let { list ->
            when (sort) {
                MarketSort.SYMBOL -> list.sortedBy { it.symbolInfo.symbol }
                MarketSort.SPREAD -> list.sortedBy { it.spreadPips }
                MarketSort.CHANGE_PCT -> list.sortedWith(compareByDescending<SymbolMarketRow> { it.dailyChangePct != null }.thenByDescending { it.dailyChangePct ?: Double.NEGATIVE_INFINITY })
            }
        }

        MarketUiState(
            rows = filtered,
            searchQuery = query,
            showOnlyFavorites = onlyFavs,
            sortOption = sort,
            connectionStatus = connStatus,
            dataSourceType = dsType
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), MarketUiState())

    init {
        viewModelScope.launch {
            marketDataRepository.initializeSymbolsIfNeeded()
            marketDataRepository.provider.connect()

            // React to changes in the available symbol list, including symbols added
            // after initial repository initialization. Avoid duplicate subscriptions.
            marketDataRepository.symbols.collect { symbols ->
                val currentSymbols = symbols.map { it.symbol }.toSet()
                val removed = symbolTickJobs.keys - currentSymbols
                removed.forEach { symbol ->
                    symbolTickJobs.remove(symbol)?.cancel()
                }
                if (removed.isNotEmpty()) {
                    ticksMap.update { current -> current.filterKeys { it in currentSymbols } }
                }
                currentSymbols.forEach { symbol ->
                    if (symbol !in symbolTickJobs) {
                        symbolTickJobs[symbol] = launch {
                            marketDataRepository.observeTicks(symbol).collect { tick ->
                                if (tick.symbol == symbol) {
                                    ticksMap.update { current -> current + (symbol to tick) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    fun updateSearchQuery(query: String) {
        _searchQuery.value = query
    }

    fun toggleFavoritesFilter() {
        _showOnlyFavorites.value = !_showOnlyFavorites.value
    }

    fun setSortOption(sort: MarketSort) {
        _sortOption.value = sort
    }

    fun toggleSymbolFavorite(symbol: String, currentFav: Boolean) {
        viewModelScope.launch {
            marketDataRepository.toggleFavorite(symbol, !currentFav)
        }
    }
}
