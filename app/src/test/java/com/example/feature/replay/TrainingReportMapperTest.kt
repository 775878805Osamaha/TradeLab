package com.example.feature.replay

import org.junit.Assert.*
import org.junit.Test

class TrainingReportMapperTest {
    @Test fun importingExistingTrainingKeepsEquityObservedBeforeRoomRegistration() {
        val state=ReplayUiState(initialBalance=100.0,currentBalance=95.0,currentEquity=95.0,
            equitySamples=listOf(ReplayEquitySample(1,90.0,100.0,1000),ReplayEquitySample(2,95.0,95.0,2000)))
        val report=TrainingReportMapper.report(TrainingSessionSnapshot(state,emptyList(),1),emptyList(),5000)
        assertEquals(3,report.curve.size)
        assertEquals(1000L,report.curve.first().timestamp)
        assertEquals(90.0,report.curve[1].equity,0.0)
        assertEquals(10.0,report.maxDrawdown,0.0)
        assertEquals(95.0,report.curve.last().balance,0.0)
    }
    @Test fun emptyReplayStillShowsFundedAccountBaseline() {
        val state=ReplayUiState(initialBalance=250.0,currentBalance=250.0,currentEquity=250.0)
        val report=TrainingReportMapper.report(TrainingSessionSnapshot(state,emptyList(),1),emptyList(),1234)
        assertEquals(1,report.curve.size)
        assertEquals(1234L,report.curve.single().timestamp)
        assertEquals(250.0,report.curve.single().balance,0.0)
        assertEquals(0.0,report.maxDrawdown,0.0)
    }

    @Test fun equityPeakAndDrawdownAreComputedFromReplaySamples() {
        val state=ReplayUiState(initialBalance=100.0,currentBalance=110.0,currentEquity=110.0,
            equitySamples=listOf(ReplayEquitySample(1,120.0,120.0,1000),
                ReplayEquitySample(2,90.0,90.0,2000),
                ReplayEquitySample(3,110.0,110.0,3000)))
        val report=TrainingReportMapper.report(TrainingSessionSnapshot(state,emptyList(),1),emptyList(),500)
        assertEquals(30.0,report.maxDrawdown,0.0)
        assertEquals(30.0,report.curve[2].drawdown,0.0)
    }

    @Test(expected=IllegalArgumentException::class)
    fun invalidReplayBalanceCannotBecomeResultsReport() {
        val state=ReplayUiState(initialBalance=100.0,currentBalance=Double.NaN,currentEquity=100.0)
        TrainingReportMapper.report(TrainingSessionSnapshot(state,emptyList(),1),emptyList(),1000)
    }

    @Test(expected=IllegalArgumentException::class)
    fun unexpectedExecutionTimestampCannotBecomeResultsReport() {
        val state=ReplayUiState(initialBalance=100.0,currentBalance=100.0,currentEquity=100.0)
        TrainingReportMapper.report(TrainingSessionSnapshot(state,emptyList(),1),listOf(1000L),1000)
    }

}
