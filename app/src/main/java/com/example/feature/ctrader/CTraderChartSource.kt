package com.example.feature.ctrader

import android.content.Context
import com.example.core.market.HistoricalCandleIntegrity
import com.example.core.market.VerifiedMarketQuote
import com.example.core.model.Candle
import com.example.core.model.Tick
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Account-scoped, opt-in broker history & quotes. Never mixes Biquote with cTrader. */
class CTraderChartSource(context: Context) {
    private val appContext=context.applicationContext
    private val api=CTraderReadOnlyMarketApi(appContext)
    private val prefs=appContext.getSharedPreferences("ctrader_chart_source_v1",Context.MODE_PRIVATE)
    private val _account=MutableStateFlow(
        prefs.getString("account_id",null)?.takeIf { CTraderAuthorization.isLinked(appContext) }
    )
    val selectedAccount: StateFlow<String?> = _account.asStateFlow()
    private val symbolCache=ConcurrentHashMap<String,CTraderReadOnlyMarketApi.BrokerSymbol>()
    private val accountMutex = Mutex()

    /** cTrader owns ALL forex/metals, even when offline or not yet authorized. */
    fun isSelectedFor(symbol:String):Boolean = symbol in VerifiedMarketQuote.forexSymbols

    /** Read the user's own granted account once; never select a legacy market source. */
    suspend fun refreshAuthorizedAccount():String = authorizedAccount()

    /** A new OAuth grant may belong to a different broker account.
     * Invalidate all account-scoped symbols and quotes BEFORE discovering it.
     */
    suspend fun onSessionReauthorized():String = accountMutex.withLock {
        _account.value = null
        symbolCache.clear()
        if(!prefs.edit().remove("account_id").commit())throw IOException("تعذر مسح بيانات الحساب السابق")
        if(!CTraderAuthorization.isLinked(appContext))throw IOException("لم يتم تسجيل الدخول إلى cTrader")
        val newAccount = api.accounts().firstOrNull()
            ?: throw IOException("لم يتم العثور على حساب وسيط مرخص")
        if(!prefs.edit().putString("account_id",newAccount.accountId).commit())
            throw IOException("تعذر حفظ حساب cTrader الجديد")
        _account.value = newAccount.accountId
        newAccount.accountId
    }

    private suspend fun authorizedAccount():String {
        if(!CTraderAuthorization.isLinked(appContext))
            throw IOException("يلزم تسجيل الدخول إلى cTrader للحصول على أسعار الفوركس")
        _account.value?.let { return it }
        return accountMutex.withLock {
            _account.value?.let { return@withLock it }
            val accounts=api.accounts()
            val account=accounts.firstOrNull()
                ?: throw IOException("لا يوجد حساب مرخص في cTrader")
            if(!prefs.edit().putString("account_id",account.accountId).commit())
                throw IOException("تعذر حفظ حساب cTrader")
            _account.value=account.accountId
            account.accountId
        }
    }

    fun disable() {
        check(prefs.edit().remove("account_id").commit())
        _account.value=null
        symbolCache.clear()
    }

    private suspend fun resolveSymbol(account:String,symbol:String):CTraderReadOnlyMarketApi.BrokerSymbol {
        val key=account+":"+symbol
        symbolCache[key]?.let { return it }
        val candidates=api.symbols(account)
        val selected=candidates.firstOrNull { it.name.equals(symbol,true) }
            ?: candidates.firstOrNull {
                it.name.uppercase().replace("/","").replace(" ","").startsWith(symbol.uppercase())
            } ?: throw IOException("وسيط cTrader لا يوفر الرمز "+symbol)
        symbolCache[key]=selected
        return selected
    }

    private fun CTraderReadOnlyMarketApi.BrokerQuote.toTick(symbol:String,now:Long):Tick {
        val actualBid=bid ?: throw IOException("لم يصل Bid من cTrader")
        val actualAsk=ask ?: throw IOException("لم يصل Ask من cTrader")
        val quoteTime=timestamp ?: throw IOException("لم يصل توقيت السعر من cTrader")
        val tick=Tick(symbol,actualBid,actualAsk,(actualBid+actualAsk)/2.0,quoteTime,"CTRADER_REST")
        if(!VerifiedMarketQuote.isVerified(tick,symbol,now))
            throw IOException("سعر cTrader قديم أو غير صالح")
        return tick
    }

    /** A diagnostic validation only; cTrader is always the exclusive forex source. */
    suspend fun validateAndEnableGold():String {
        if(!CTraderAuthorization.isLinked(appContext))throw IOException("اربط حساب cTrader أولًا")
        val accounts=api.accounts()
        if(accounts.isEmpty())throw IOException("لا توجد حسابات cTrader مرخصة")
        val now=System.currentTimeMillis()
        val interval=Timeframe.M15.minutes*60_000L
        val lastClosed=now/interval*interval-interval
        var lastError:Exception?=null
        for(acc in accounts) {
            currentCoroutineContext().ensureActive()
            try {
                val broker=resolveSymbol(acc.accountId,"XAUUSD")
                val tick=api.spot(acc.accountId,broker.symbolId).toTick("XAUUSD",System.currentTimeMillis())
                val bars=fetchFor(acc.accountId,"XAUUSD",Timeframe.M15,
                    (lastClosed-48L*3_600_000L).coerceAtLeast(0L),lastClosed,300)
                if(bars.isEmpty())throw IOException("لا تتوفر شموع ذهب مغلقة من cTrader")
                if(!prefs.edit().putString("account_id",acc.accountId).commit())
                    throw IOException("تعذر حفظ اختيار cTrader")
                _account.value=acc.accountId
                return "اعتمد cTrader للشارت، الحساب "+acc.accountId+"، الذهب "+
                    broker.name+"، Bid "+tick.bid+"، Ask "+tick.ask
            } catch(e:CancellationException) { throw e }
            catch(e:Exception) { lastError=e }
        }
        throw IOException(lastError?.message ?: "تعذر التحقق من سعر الذهب والشموع")
    }

    suspend fun latestTick(symbol:String):Tick {
        val account=authorizedAccount()
        val broker=resolveSymbol(account,symbol)
        return api.spot(account,broker.symbolId).toTick(symbol,System.currentTimeMillis())
    }

    fun observeTicks(symbol:String):Flow<Tick> = flow {
        while(currentCoroutineContext().isActive && isSelectedFor(symbol)) {
            try { emit(latestTick(symbol));delay(3_000L) }
            catch(e:CancellationException) { throw e }
            catch(_:Exception) { delay(5_000L) }
        }
    }

    suspend fun candles(symbol:String,timeframe:Timeframe,from:Long,to:Long):List<Candle> {
        val account=authorizedAccount()
        require(from>=0&&to>=from)
        return fetchFor(account,symbol,timeframe,from,to,20_000)
    }

    /**
     * Request historical bars backwards using the Open API's count limit, without
     * downloading every empty calendar slot.  Each call is bounded by a
     * timeframe-appropriate maximum time span.  Weekend/holiday gaps do not
     * manufacture OHLC bars.  A call that fails must not be treated as empty.
     */
    suspend fun candlesBefore(symbol:String,timeframe:Timeframe,oldestOpen:Long):List<Candle> {
        val account=authorizedAccount()
        val broker=resolveSymbol(account,symbol)
        val h2=timeframe==Timeframe.H2
        val sourceTimeframe=if(h2)Timeframe.H1 else timeframe
        val sourceInterval=sourceTimeframe.minutes*60_000L
        val outputInterval=timeframe.minutes*60_000L
        if(oldestOpen<outputInterval) return emptyList()
        var end=oldestOpen-sourceInterval
        val period=sourceTimeframe.code
        val batchCount=if(h2)1000 else 500
        for(attempt in 0 until 8) {
            currentCoroutineContext().ensureActive()
            if(end<0L)break
            val span=CTraderHistoryPaging.windowSpan(timeframe)
            val start=(end-span+sourceInterval).coerceAtLeast(0L)
            // Broker's count is a backwards-facing ceiling relative to toTimestamp.
            // Avoid huge chronological downloads to scan closed market sessions.
            val fetched=api.candles(account,broker.symbolId,period,start,end,batchCount)
            val verifiedRaw=fetched.sortedBy { it.timestampMs }
            if(verifiedRaw.zipWithNext().any { (a,b) -> a.timestampMs==b.timestampMs })
                throw IOException("شموع cTrader التاريخية مكررة")
            val converted=if(h2)CTraderBarConversion.aggregateH2(symbol,verifiedRaw) else
                verifiedRaw.map {
                    Candle(symbol,timeframe,it.timestampMs,it.timestampMs+outputInterval,
                        it.open,it.high,it.low,it.close,it.volume.toDouble(),"CTRADER_HISTORICAL")
                }
            val now=System.currentTimeMillis()
            val closed=converted.filter { bar ->
                bar.openTime>=start && bar.openTime<oldestOpen &&
                    bar.closeTime<=now && bar.openTime+outputInterval<=oldestOpen
            }
            if(closed.isNotEmpty())return HistoricalCandleIntegrity.validate(
                closed.takeLast(500),start,oldestOpen,
                expectedSource="CTRADER_HISTORICAL",
                expectedSymbol=symbol,expectedTimeframe=timeframe
            )
            if(start<=0L)break
            end=start-sourceInterval
        }
        return emptyList()
    }

    private suspend fun fetchFor(account:String,symbol:String,timeframe:Timeframe,
        from:Long,to:Long,maxBars:Int):List<Candle> {
        val broker=resolveSymbol(account,symbol)
        val h2=timeframe==Timeframe.H2
        val period=if(h2)"H1" else timeframe.code
        val sourceInterval=(if(h2)Timeframe.H1.minutes else timeframe.minutes)*60_000L
        val outputInterval=timeframe.minutes*60_000L
        val upper=if(h2)to+sourceInterval else to
        val pageSize=minOf(900L,(89L*86_400_000L/sourceInterval).coerceAtLeast(1L))
        val raw=ArrayList<CTraderReadOnlyMarketApi.BrokerCandle>()
        var cursor=from
        var pages=0
        while(cursor<=upper) {
            currentCoroutineContext().ensureActive()
            if(++pages>48)throw IOException("التاريخ المطلوب كبير؛ حمّله على دفعات")
            val end=minOf(upper,cursor+(pageSize-1L)*sourceInterval)
            raw.addAll(api.candles(account,broker.symbolId,period,cursor,end,pageSize.toInt()))
            if(raw.size>maxBars*(if(h2)2 else 1)+10)throw IOException("عدد شموع غير متوقع")
            cursor=end+sourceInterval
        }
        val ordered=raw.sortedBy { it.timestampMs }
        if(ordered.zipWithNext().any { (a,b) -> a.timestampMs==b.timestampMs })
            throw IOException("شموع cTrader مكررة")
        val output=if(h2)CTraderBarConversion.aggregateH2(symbol,ordered) else ordered.map {
            Candle(symbol,timeframe,it.timestampMs,it.timestampMs+outputInterval,
                it.open,it.high,it.low,it.close,it.volume.toDouble(),"CTRADER_HISTORICAL")
        }
        val now=System.currentTimeMillis()
        val closed=output.filter { it.openTime in from..to && it.closeTime<=now }
        return HistoricalCandleIntegrity.validate(closed,from,to+outputInterval,
            expectedSymbol=symbol,expectedTimeframe=timeframe,expectedSource="CTRADER_HISTORICAL")
    }
}

/** H2 exists in TradeLab, but not cTrader: aggregate only consecutive genuine H1 bars. */
object CTraderBarConversion {
    fun aggregateH2(symbol:String,bars:List<CTraderReadOnlyMarketApi.BrokerCandle>):List<Candle> {
        val period=7_200_000L
        return bars.groupBy { Math.floorDiv(it.timestampMs,period)*period }.values.mapNotNull { part ->
            val sorted=part.sortedBy { it.timestampMs }
            if(sorted.size!=2 || sorted[0].timestampMs%period!=0L ||
                sorted[1].timestampMs!=sorted[0].timestampMs+3_600_000L)return@mapNotNull null
            Candle(symbol,Timeframe.H2,sorted[0].timestampMs,sorted[0].timestampMs+period,
                sorted[0].open,maxOf(sorted[0].high,sorted[1].high),
                minOf(sorted[0].low,sorted[1].low),sorted[1].close,
                sorted.sumOf { it.volume }.toDouble(),"CTRADER_HISTORICAL")
        }
    }
}
