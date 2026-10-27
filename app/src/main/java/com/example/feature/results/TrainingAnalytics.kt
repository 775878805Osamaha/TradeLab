package com.example.feature.results

import com.example.core.model.*
import com.example.core.statistics.StatisticsCalculator
import java.math.BigDecimal
import java.util.Calendar
import kotlin.math.sqrt

data class TrainingDay(val time:Long,val pnl:Double,val count:Int,val wins:Int,val losses:Int,val closing:Double)
data class TrainingAnalytics(
    val opening:Double,val closing:Double,val deposits:Double,val metrics:PerformanceMetrics,
    val curve:List<EquityPoint>,val trades:List<TradeJournalEntry>,val recordedAt:List<Long>,
    val days:List<TrainingDay>,val start:Long,val end:Long,val floating:Double
)

/** Calendar filters use training registration time. Market timestamps stay intact in the journal.
 * Initial funding is the opening capital, disclosed as a deposit, never added a second time.
 * Cash aggregates use decimal arithmetic; execution's bid/ask already includes spread.
 */
object TrainingAnalyticsCalculator {
    private fun sum(values:Iterable<Double>)=values.fold(BigDecimal.ZERO){a,v->a+BigDecimal.valueOf(v)}.toDouble()
    fun dayStart(time:Long)=Calendar.getInstance().apply { timeInMillis=time;set(Calendar.HOUR_OF_DAY,0);set(Calendar.MINUTE,0);set(Calendar.SECOND,0);set(Calendar.MILLISECOND,0) }.timeInMillis
    fun start(period:ResultsPeriod,now:Long,custom:Long?):Long? {
        if(period==ResultsPeriod.ALL)return null
        if(period==ResultsPeriod.CUSTOM)return custom?.let(::dayStart)
        return Calendar.getInstance().apply {
            timeInMillis=dayStart(now)
            when(period){
                ResultsPeriod.YEAR->set(Calendar.DAY_OF_YEAR,1)
                ResultsPeriod.SIX_MONTHS->add(Calendar.MONTH,-6)
                ResultsPeriod.THREE_MONTHS->add(Calendar.MONTH,-3)
                ResultsPeriod.MONTH->set(Calendar.DAY_OF_MONTH,1)
                ResultsPeriod.WEEK->{firstDayOfWeek=Calendar.SATURDAY;set(Calendar.DAY_OF_WEEK,Calendar.SATURDAY)}
                else->Unit
            }
        }.timeInMillis
    }
    fun calculate(report:ReplayReport, period:ResultsPeriod=ResultsPeriod.ALL, now:Long=System.currentTimeMillis(),customStart:Long?=null,customEnd:Long?=null):TrainingAnalytics {
        require(report.account.initialBalance.isFinite())
        val end=if(period==ResultsPeriod.CUSTOM && customEnd!=null) minOf(now,dayStart(customEnd)+86_400_000L-1) else now
        val cutoff=start(period,now,customStart)
        require(cutoff==null || cutoff<=end){"Invalid date range"}
        val ordered=report.trades.mapIndexed { i,t -> t to (report.recordedAt.getOrNull(i) ?: t.closeTime) }
            .filter { it.second<=end && it.first.netProfitLoss.isFinite() }
            .sortedWith(compareBy<Pair<TradeJournalEntry,Long>> { it.second })
        val earlier=ordered.filter { cutoff!=null && it.second<cutoff }
        val included=ordered.filter { cutoff==null || it.second>=cutoff }
        val opening=sum(listOf(report.account.initialBalance)+earlier.map { it.first.netProfitLoss })
        val net=sum(included.map { it.first.netProfitLoss })
        val closing=sum(listOf(opening,net))
        var ledgerBalance=report.account.initialBalance
        val availableCurve=if(report.curve.isNotEmpty())report.curve else ordered.map { (trade,at)->
            ledgerBalance=sum(listOf(ledgerBalance,trade.netProfitLoss));EquityPoint(at,ledgerBalance,ledgerBalance,0.0,ledgerBalance)
        }
        val series=availableCurve.filter { it.timestamp<=end && it.equity.isFinite() && it.balance.isFinite() }.sortedBy { it.timestamp }
        val begin=cutoff ?: minOf(report.fundedAt.takeIf { it>0 } ?: now,series.firstOrNull()?.timestamp ?: now,included.firstOrNull()?.second ?: now)
        val previous=series.lastOrNull { it.timestamp<begin }
        val baseEquity=previous?.equity ?: opening
        var peak=baseEquity
        val curve=listOf(EquityPoint(begin,opening,baseEquity,0.0,peak))+series.filter { it.timestamp>=begin }.map {
            peak=maxOf(peak,it.equity);it.copy(drawdown=(peak-it.equity).coerceAtLeast(0.0),highWatermark=peak)
        }
        val trades=included.map { it.first }
        val floating=curve.last().equity-curve.last().balance
        val raw=StatisticsCalculator.calculate(opening,trades,closing+floating)
        var dailyBalance=opening
        val days=included.groupBy { dayStart(it.second) }.toSortedMap().entries.map { (day,rows) ->
            val dayPnl=sum(rows.map { it.first.netProfitLoss })
            dailyBalance=sum(listOf(dailyBalance,dayPnl))
            val dayClose=dailyBalance
            TrainingDay(day,sum(rows.map { it.first.netProfitLoss }),rows.size,rows.count { it.first.netProfitLoss>0 },rows.count { it.first.netProfitLoss<0 },dayClose)
        }
        var balance=opening
        val returns=days.mapNotNull { day -> val before=balance;balance=sum(listOf(balance,day.pnl));if(before>0)day.pnl/before else null }
        val avg=returns.takeIf { it.isNotEmpty() }?.average() ?:0.0
        val deviation=if(returns.size>=2)sqrt(returns.sumOf { (it-avg)*(it-avg) }/(returns.size-1)) else 0.0
        var win=0;var loss=0;var maxWin=0;var maxLoss=0
        trades.forEach { if(it.netProfitLoss>0){win++;loss=0}else if(it.netProfitLoss<0){loss++;win=0}else{win=0;loss=0};maxWin=maxOf(maxWin,win);maxLoss=maxOf(maxLoss,loss) }
        val risk=trades.filter { it.stopLoss!=null && kotlin.math.abs(it.entryPrice-it.stopLoss)>0 && it.rMultiple.isFinite() }
        val dd=curve.maxOf { it.drawdown }
        val metrics=raw.copy(finalBalance=closing,netProfit=net,returnPct=if(opening>0)net/opening*100 else 0.0,
            maxDrawdown=dd,maxDrawdownPct=curve.maxOf { it.drawdownPercentage },
            profitFactor=if(raw.grossLoss>0)raw.grossProfit/raw.grossLoss else null,
            expectancy=if(trades.isNotEmpty())net/trades.size else null,
            sharpeRatio=if(deviation>0)avg/deviation else null,
            recoveryFactor=if(dd>0)net/dd else null,maxConsecutiveWins=maxWin,maxConsecutiveLosses=maxLoss,
            avgRMultiple=if(risk.isNotEmpty())risk.map { it.rMultiple }.average() else null)
        val deposits=if(report.fundedAt<=end && (cutoff==null || report.fundedAt>=cutoff))report.account.initialBalance else 0.0
        return TrainingAnalytics(opening,closing,deposits,metrics,curve,trades,included.map { it.second },days,begin,end,floating)
    }
}
