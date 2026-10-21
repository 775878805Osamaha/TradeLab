package com.example.core.backtest

import com.example.core.model.PositionSizingMode
import com.example.core.model.Timeframe
import com.example.core.strategy.Signal
import com.example.core.strategy.SignalAction
import com.example.core.strategy.Strategy
import com.example.core.strategy.StrategyContext
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BacktestConfigValidationTest {
    private val holdStrategy = object : Strategy {
        override val id = "TEST_HOLD"
        override val name = "Hold"
        override val description = "No trades"
        override val defaultParameters: Map<String, Any> = emptyMap()
        override fun onCandle(context: StrategyContext, parameters: Map<String, Any>) =
            Signal(SignalAction.HOLD)
    }

    private fun config() = BacktestConfig(
        strategy = holdStrategy,
        symbol = "BTCUSDT",
        timeframe = Timeframe.M1
    )

    @Test fun acceptsValidDefaults() {
        assertTrue(config().validate().isSuccess)
    }

    @Test fun rejectsNonFiniteExecutionCosts() {
        assertFalse(config().copy(spreadPips = Double.NaN).validate().isSuccess)
        assertFalse(config().copy(slippagePips = Double.POSITIVE_INFINITY).validate().isSuccess)
        assertFalse(config().copy(commissionPerLot = Double.NaN).validate().isSuccess)
        assertFalse(config().copy(swapPerLotDaily = Double.NEGATIVE_INFINITY).validate().isSuccess)
    }

    @Test fun rejectsNonFiniteBalanceAndLeverage() {
        assertFalse(config().copy(initialBalance = Double.NaN).validate().isSuccess)
        assertFalse(config().copy(leverage = Double.POSITIVE_INFINITY).validate().isSuccess)
    }

    @Test fun rejectsInvalidSizing() {
        assertFalse(config().copy(fixedLot = Double.NaN).validate().isSuccess)
        assertFalse(config().copy(positionSizingMode = PositionSizingMode.RISK_PERCENTAGE,
            riskPercentage = Double.NaN).validate().isSuccess)
        assertFalse(config().copy(positionSizingMode = PositionSizingMode.FIXED_MONETARY_RISK,
            fixedRiskAmount = Double.POSITIVE_INFINITY).validate().isSuccess)
    }

    @Test fun rejectsInvertedDatesAndDisabledDirections() {
        assertFalse(config().copy(startTime = 2000L, endTime = 1000L).validate().isSuccess)
        assertFalse(config().copy(allowLong = false, allowShort = false).validate().isSuccess)
    }
}
