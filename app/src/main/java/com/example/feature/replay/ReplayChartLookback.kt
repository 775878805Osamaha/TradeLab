package com.example.feature.replay

import com.example.core.market.HistoricalCandleIntegrity
import com.example.core.market.VerifiedMarketQuote
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.feature.chart.history.ChartHistoryPaging
import java.io.IOException

/**
 * Validates and merges a market-history page without ever exposing a candle
 * beyond the beginning of the Replay engine's immutable dataset.
 *
 * Real market closures are retained as gaps; no artificial OHLC bars are made.
 * Adjacent pages may overlap because cTrader's toTimestamp is inclusive.
 * Exact duplicate OHLC bars can be deduplicated, but conflicting prices cause
 * the entire page to fail rather than silently rewrite historical trades.
 */
object ReplayChartLookback {
    class InvalidPage(val reason: Reason, explanation: String): IOException(explanation)
    enum class Reason {
        SYMBOL, TIMEFRAME, SOURCE, UNFINISHED, FUTURE_REPLAY, DUPLICATE_CONFLICT,
        UNORDERED_EXISTING, EMPTY_RANGE
    }

    private fun allowedSources(symbol:String):Set<String> =
        if (symbol in VerifiedMarketQuote.forexSymbols)
            setOf("CTRADER_HISTORICAL")
        else if (symbol in setOf("BTCUSDT","ETHUSDT"))
            setOf("BINANCE_HISTORICAL","BINANCE_HISTORICAL_CACHED")
        else emptySet()

    private fun checkIdentity(bar:Candle, symbol:String,timeframe:Timeframe,
                              sources:Set<String>,boundary:Long) {
        if(!bar.symbol.equals(symbol,ignoreCase=true))
            throw InvalidPage(Reason.SYMBOL,"رمز الشموع الأقدم يختلف عن جلسة Replay.")
        if(bar.timeframe!=timeframe)
            throw InvalidPage(Reason.TIMEFRAME,"فريم الشموع الأقدم لا يطابق فريم جلسة Replay.")
        if(bar.source !in sources)
            throw InvalidPage(Reason.SOURCE,"رفضت شموعًا من مصدر مختلف عن cTrader/Binance المعتمد.")
        if(bar.openTime>=boundary || bar.closeTime>boundary)
            throw InvalidPage(Reason.FUTURE_REPLAY,"الدفعة تجاوزت بداية جلسة Replay؛ لم تُعرض شموع مستقبلية.")
        if(!bar.isValid() || bar.closeTime-bar.openTime>timeframe.minutes*60_000L ||
            bar.openTime<0L)
            throw InvalidPage(Reason.UNFINISHED,"توجد شمعة غير صحيحة في التاريخ المسترجع.")
    }

    private fun sameMarketBar(a:Candle,b:Candle):Boolean =
        a.symbol.equals(b.symbol,ignoreCase=true) &&
        a.timeframe==b.timeframe &&
        a.openTime==b.openTime && a.closeTime==b.closeTime &&
        a.open==b.open && a.high==b.high && a.low==b.low &&
        a.close==b.close && a.volume==b.volume &&
        a.source==b.source

    fun prepend(
        existing:List<Candle>,
        incoming:List<Candle>,
        replayFirstOpen:Long,
        symbol:String,
        timeframe:Timeframe
    ):List<Candle> {
        if(incoming.isEmpty())return existing
        require(replayFirstOpen>0 && timeframe.minutes>0)
        val sources=allowedSources(symbol)
        if(sources.isEmpty())
            throw InvalidPage(Reason.SOURCE,"رمز التاريخ غير مدعوم لدى مزود البيانات.")

        // Validate the whole page before merging; a partial failure is not
        // treated as an empty market session or a reason to use a second source.
        incoming.forEach { checkIdentity(it,symbol,timeframe,sources,replayFirstOpen) }
        existing.forEach { checkIdentity(it,symbol,timeframe,sources,replayFirstOpen) }
        if(existing.zipWithNext().any { (a,b) -> a.openTime>=b.openTime })
            throw InvalidPage(Reason.UNORDERED_EXISTING,"تاريخ Replay المحفوظ غير مرتب؛ أعد فتح الجلسة.")

        val page=incoming.sortedBy { it.openTime }
        val distinct=ArrayList<Candle>(page.size)
        for(bar in page) {
            val last=distinct.lastOrNull()
            if(last?.openTime==bar.openTime) {
                if(!sameMarketBar(last,bar))
                    throw InvalidPage(Reason.DUPLICATE_CONFLICT,
                        "تعارضت أسعار شمعتين بالتوقيت نفسه من الوسيط.")
                continue
            }
            distinct.add(bar)
        }

        try {
            HistoricalCandleIntegrity.validate(
                distinct,distinct.first().openTime,replayFirstOpen,
                expectedSymbol=symbol,expectedTimeframe=timeframe
            )
        } catch(e:IllegalArgumentException) {
            throw InvalidPage(Reason.UNFINISHED,
                "بيانات الشموع الأقدم غير مكتملة أو غير متوافقة مع توقيت الفريم.")
        }

        // A provider's inclusive timestamp may repeat one or more candles
        // already loaded. Only strictly identical OHLC rows may overlap.
        var i=0
        var j=0
        while(i<existing.size && j<distinct.size) {
            when {
                existing[i].openTime<distinct[j].openTime -> i++
                existing[i].openTime>distinct[j].openTime -> j++
                else -> {
                    if(!sameMarketBar(existing[i],distinct[j]))
                        throw InvalidPage(Reason.DUPLICATE_CONFLICT,
                            "أعاد الوسيط أسعارًا مختلفة للشمعة نفسها؛ لم يتم دمج الدفعة.")
                    i++;j++
                }
            }
        }
        return ChartHistoryPaging.merge(existing,distinct)
    }
}
