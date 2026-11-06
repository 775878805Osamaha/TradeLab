package com.example.feature.chart.history

import com.example.core.market.NoHistoricalCandlesException
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class ChartHistoryRetryPolicyTest {
    @Test fun aVerifiedEmptyBrokerWindowAllowsSearchingOlderSessions() {
        assertTrue(ChartHistoryRetryPolicy.shouldSearchOlderSession(NoHistoricalCandlesException("XAUUSD")))
    }

    @Test fun missingBrokerAuthorizationFailsWithoutRepeatingHistoricalRequests() {
        assertFalse(ChartHistoryRetryPolicy.shouldSearchOlderSession(IOException("اربط حساب cTrader في الإعدادات")))
    }

    @Test fun invalidBarsAndHttpFailuresAreNotTreatedAsClosedMarkets() {
        assertFalse(ChartHistoryRetryPolicy.shouldSearchOlderSession(IllegalArgumentException("Misaligned candle timestamp")))
        assertFalse(ChartHistoryRetryPolicy.shouldSearchOlderSession(IOException("HTTP 503")))
    }
}
