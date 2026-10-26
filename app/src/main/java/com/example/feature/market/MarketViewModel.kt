package com.example.feature.market

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.model.*
import com.example.core.market.VerifiedMarketQuote
import com.example.data.repository.MarketDataRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

enum class MarketSort(val label: String) { DEFAULT("ترتيب الأصول"), SYMBOL("الرمز"), SPREAD("أقل سبريد"), CHANGE_PCT("أعلى ارتفاع"), LOSERS("أعلى انخفاض"), FAVORITES("المفضلة") }
enum class MarketCategory(val label:String,val category:String?) { ALL("الكل",null), CRYPTO("العملات الرقمية","Crypto"), FOREX("الفوركس","Forex"), STOCKS("الأسهم","Stocks"), INDICES("المؤشرات","Indices"), METALS("المعادن","Metals"), FAVORITES("المفضلة",null) }
data class MarketUiState(val rows:List<MarketQuoteSnapshot> = emptyList(), val searchQuery:String="",val category:MarketCategory=MarketCategory.ALL,val sortOption:MarketSort=MarketSort.DEFAULT,val compact:Boolean=true,val loading:Boolean=true)

@OptIn(FlowPreview::class)
class MarketViewModel(private val marketDataRepository: MarketDataRepository):ViewModel() {
    private val query=MutableStateFlow("")
    private val category=MutableStateFlow(MarketCategory.ALL)
    private val sort=MutableStateFlow(MarketSort.DEFAULT)
    private val compact=MutableStateFlow(true)
    private val ticks=MutableStateFlow<Map<String,Tick>>(emptyMap())
    private val histories=MutableStateFlow<Map<String,List<Candle>>>(emptyMap())
    private val clock=flow { while(currentCoroutineContext().isActive){emit(System.currentTimeMillis());delay(1000)} }
    private val rows=combine(marketDataRepository.symbols,ticks,histories,clock){ symbols,prices,bars,now->symbols.map{MarketQuoteSnapshot.from(it,prices[it.symbol],bars[it.symbol].orEmpty(),now)} }
    private val filters=combine(query.debounce(120),category,sort,compact){q,c,s,v->MarketUiState(searchQuery=q,category=c,sortOption=s,compact=v)}
    val uiState=combine(rows,filters){all,f->
        val selected=all.filter { (f.searchQuery.isBlank() || it.symbol.symbol.contains(f.searchQuery,true) || it.symbol.name.contains(f.searchQuery,true)) &&
            (f.category==MarketCategory.ALL || f.category==MarketCategory.FAVORITES && it.symbol.isFavorite || f.category.category==it.symbol.category) }
        val ordered=when(f.sortOption){
            MarketSort.DEFAULT->selected.sortedWith(compareBy<MarketQuoteSnapshot>{ listOf("XAUUSD","BTCUSDT","ETHUSDT","EURUSD","GBPUSD","USDJPY","AUDUSD","USDCAD","NZDUSD","USDCHF").indexOf(it.symbol.symbol).let{n->if(n<0)Int.MAX_VALUE else n} }.thenBy{it.symbol.symbol})
            MarketSort.SYMBOL->selected.sortedBy{it.symbol.symbol}
            MarketSort.SPREAD->selected.sortedWith(compareBy<MarketQuoteSnapshot>{it.spread==null}.thenBy{it.spread})
            MarketSort.CHANGE_PCT->selected.sortedWith(compareBy<MarketQuoteSnapshot>{it.changePercent==null}.thenByDescending{it.changePercent})
            MarketSort.LOSERS->selected.sortedWith(compareBy<MarketQuoteSnapshot>{it.changePercent==null}.thenBy{it.changePercent})
            MarketSort.FAVORITES->selected.sortedWith(compareByDescending<MarketQuoteSnapshot>{it.symbol.isFavorite}.thenBy{it.symbol.symbol})
        }
        f.copy(rows=ordered,loading=false)
    }.stateIn(viewModelScope,SharingStarted.WhileSubscribed(5000),MarketUiState())
    init { viewModelScope.launch {
        marketDataRepository.initializeSymbolsIfNeeded()
        val permits=Semaphore(3)
        marketDataRepository.symbols.map{it.map{symbol->symbol.symbol}.toSet()}.distinctUntilChanged().collectLatest { symbols->
            coroutineScope { symbols.filter{VerifiedMarketQuote.supports(it)}.forEach { symbol->
                launch { marketDataRepository.provider.subscribe(symbol);marketDataRepository.observeTicks(symbol).collect{tick->if(tick.symbol==symbol)ticks.update{it+(symbol to tick)}} }
                launch(Dispatchers.IO) { while(isActive) {
                    try { permits.withPermit {
                        val interval=900000L;val to=System.currentTimeMillis()/interval*interval-interval
                        val bars=marketDataRepository.getCandles(symbol,Timeframe.M15,to-95*interval,to)
                        histories.update{it+(symbol to bars)}
                    } } catch(cancelled:CancellationException){throw cancelled} catch(_:Exception){ /* Preserve last genuine history; its timestamps control expiry. */ }
                    delay(300000)
                } }
            } }
        }
    } }
    fun updateSearchQuery(value:String){query.value=value}
    fun selectCategory(value:MarketCategory){category.value=value}
    fun setSortOption(value:MarketSort){sort.value=value}
    fun setCompact(value:Boolean){compact.value=value}
    fun toggleSymbolFavorite(symbol:String,current:Boolean){viewModelScope.launch{marketDataRepository.toggleFavorite(symbol,!current)}}
}
