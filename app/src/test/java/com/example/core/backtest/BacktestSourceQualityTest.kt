package com.example.core.backtest

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.core.strategy.Signal
import com.example.core.strategy.SignalAction
import com.example.core.strategy.Strategy
import com.example.core.strategy.StrategyContext
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class BacktestSourceQualityTest {
    private val strategy = object : Strategy {
        override val id = "source_quality_test"
        override val name = "Source quality"
        override val description = "No trading"
        override val defaultParameters: Map<String, Any> = emptyMap()
        override fun onCandle(context: StrategyContext, parameters: Map<String, Any>) =
            Signal(action = SignalAction.HOLD)
    }

    private fun bars(count: Int): List<Candle> = (0 until count).map { index ->
        val openTime = 1_700_000_000_000L + index * 900_000L
        Candle(
            symbol = "XAUUSD",
            timeframe = Timeframe.M15,
            openTime = openTime,
            closeTime = openTime + 900_000L,
            open = 2000.0,
            high = 2001.0,
            low = 1999.0,
            close = 2000.5,
            volume = 10.0
        )
    }

    private val config get() = BacktestConfig(
        strategy = strategy,
        symbol = "XAUUSD",
        timeframe = Timeframe.M15
    )

    @Test fun validSampleStillRuns() = runBlocking {
        val result = BacktestEngine().runBacktest(bars(20), config)
        assertEquals(20, result.totalCandlesProcessed)
        assertEquals(0, result.trades.size)
        assertTrue(result.equityCurve.isNotEmpty())
    }

    @Test fun emptyAndWarmupOnlySamplesAreRejected() = runBlocking {
        for (size in listOf(0, 1, 15)) {
            try {
                BacktestEngine().runBacktest(bars(size), config)
                fail("Insufficient sample accepted: $size")
            } catch (_: IllegalArgumentException) {}
        }
    }

    @Test fun badBarOutsideRequestedRangeIsNotHidden() = runBlocking {
        val sample = bars(20).toMutableList()
        sample[0] = sample[0].copy(high = 1900.0)
        try {
            BacktestEngine().runBacktest(
                sample,
                config.copy(startTime = sample[1].openTime)
            )
            fail("Corrupt bar before requested start was ignored")
        } catch (error: IllegalArgumentException) {
            assertTrue(error.message.orEmpty().contains("integrity"))
        }
    }

    @Test fun duplicateSourceTimestampIsRejected() = runBlocking {
        val sample = bars(20).toMutableList()
        sample[4] = sample[3]
        try {
            BacktestEngine().runBacktest(sample, config)
            fail("Duplicate timestamp was accepted")
        } catch (error: IllegalArgumentException) {
            assertTrue(error.message.orEmpty().contains("integrity"))
        }
    }

    @Test fun dateFilterWithTooFewBarsIsRejected() = runBlocking {
        val sample = bars(20)
        try {
            BacktestEngine().runBacktest(
                sample,
                config.copy(startTime = sample[18].openTime)
            )
            fail("Short date range was reported as successful")
        } catch (error: IllegalArgumentException) {
            assertTrue(error.message.orEmpty().contains("Insufficient"))
        }
    }
}
