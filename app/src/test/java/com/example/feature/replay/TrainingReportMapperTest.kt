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
}
