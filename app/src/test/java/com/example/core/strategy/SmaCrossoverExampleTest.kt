package com.example.core.strategy

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.core.model.VirtualAccount
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SmaCrossoverExampleTest {
    private val strategy = SmaCrossoverExample()
    private val params = mapOf<String, Any>(
        "fastPeriod" to 2,
        "slowPeriod" to 3,
        "stopLossPercent" to 0.5,
        "takeProfitPercent" to 1.0
    )

    private fun context(closes: List<Double>): StrategyContext {
        val bars = closes.mapIndexed { i, price ->
            Candle("XAUUSD", Timeframe.M15, i * 900_000L + 1_700_000_000_000L,
                (i + 1) * 900_000L + 1_700_000_000_000L,
                price, price + 1.0, price - 1.0, price, 100.0, "TEST")
        }
        return StrategyContext("XAUUSD", Timeframe.M15, bars.last(), bars,
            emptyList(), VirtualAccount(id = 1, name = "Test", balance = 100.0))
    }

    @Test fun crossoverRequiresCompletedPriorBarsAndNeverUsesFutureCandles() {
        assertTrue(StrategyValidator.validate(strategy, params).isValid)
        assertEquals(SignalAction.HOLD, strategy.onCandle(context(listOf(100.0, 100.0, 100.0)), params).action)
        assertEquals(SignalAction.HOLD, strategy.onCandle(context(listOf(100.0, 100.0, 100.0, 100.0)), params).action)
        val up = strategy.onCandle(context(listOf(100.0, 100.0, 100.0, 100.0, 101.0)), params)
        assertEquals(SignalAction.BUY, up.action)
        assertTrue(up.stopLoss!! < 101.0 && up.takeProfit!! > 101.0)
        val down = strategy.onCandle(context(listOf(100.0, 100.0, 100.0, 101.0, 90.0)), params)
        assertEquals(SignalAction.SELL, down.action)
        assertTrue(down.stopLoss!! > 90.0 && down.takeProfit!! < 90.0)
    }

    @Test fun wrongParametersDoNotGenerateOrders() {
        val invalid = params + ("fastPeriod" to 5)
        assertTrue(!StrategyValidator.validate(strategy, invalid).isValid)
        assertEquals(SignalAction.HOLD,
            strategy.onCandle(context(listOf(100.0, 100.0, 100.0, 100.0, 101.0)), invalid).action)
    }
}
