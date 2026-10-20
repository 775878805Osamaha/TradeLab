package com.example

import com.example.core.execution.*
import com.example.core.model.*
import org.junit.Assert.*
import org.junit.Test

class MarketOrderSafetyTests {
    private val account = VirtualAccount(
        id = 1L, name = "Execution safety", balance = 100000.0,
        equity = 100000.0, freeMargin = 100000.0, leverage = 100.0
    )
    private fun execute(engine: ExecutionEngine, symbol: String, tick: Tick) =
        engine.executeMarketOrder(account, symbol, OrderSide.BUY, 0.01, tick, null, null)

    @Test fun marketOrderRejectsAnotherInstrumentsQuote() {
        val tick = Tick(symbol = "ETHUSDT", bid = 100.0, ask = 100.1)
        assertTrue(execute(ExecutionEngine(), "BTCUSDT", tick) is ExecutionResult.Error)
    }

    @Test fun marketOrderRejectsNonFiniteSlippage() {
        val tick = Tick(symbol = "BTCUSDT", bid = 100.0, ask = 100.1)
        val engine = ExecutionEngine(ExecutionConfig(slippagePips = Double.NaN))
        assertTrue(execute(engine, "BTCUSDT", tick) is ExecutionResult.Error)
    }

    @Test fun marketOrderRejectsFillBelowZeroAfterSlippage() {
        val tick = Tick(symbol = "BTCUSDT", bid = 100.0, ask = 100.1)
        val engine = ExecutionEngine(ExecutionConfig(slippagePips = 1e12))
        assertTrue(engine.executeMarketOrder(account, "BTCUSDT", OrderSide.SELL, 0.01, tick, null, null) is ExecutionResult.Error)
    }
}
