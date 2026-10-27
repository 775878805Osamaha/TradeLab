package com.example.feature.replay

import com.example.core.model.*

object TrainingReportMapper {
    fun report(saved:TrainingSessionSnapshot, recordedAt:List<Long>, fundedAt:Long):ReplayReport {
        val s=saved.state
        var peak=s.initialBalance
        val samples=s.equitySamples.map { sample ->
            peak=maxOf(peak,sample.equity)
            EquityPoint(sample.timestamp,sample.balance,sample.equity,(peak-sample.equity).coerceAtLeast(0.0),peak)
        }
        val baseline=EquityPoint(fundedAt,s.initialBalance,s.initialBalance,0.0,s.initialBalance)
        val curve=listOf(baseline)+samples.filter { it.timestamp>=fundedAt }
        val account=VirtualAccount(id=9999,name="حساب التدريب",initialBalance=s.initialBalance,balance=s.currentBalance,
            equity=s.currentEquity,mode=AccountMode.REPLAY)
        return ReplayReport(account,s.openPositions,s.pendingOrders,s.closedTrades.mapIndexed { i,t -> t.copy(id=i+1L) },curve,
            curve.maxOfOrNull { it.drawdown }?:0.0,curve.maxOfOrNull { it.drawdownPercentage }?:0.0,recordedAt,fundedAt)
    }
}
