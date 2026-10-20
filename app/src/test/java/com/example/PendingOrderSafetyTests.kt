package com.example

import com.example.core.execution.ExecutionEngine
import com.example.core.execution.ExecutionConfig
import com.example.core.execution.ExecutionResult
import com.example.core.model.*
import org.junit.Assert.*
import org.junit.Test

class PendingOrderSafetyTests {
    private val engine = ExecutionEngine(ExecutionConfig(slippagePips = 0.0, defaultCommissionPerLot = 0.0))
    private val account = VirtualAccount(
        id = 1L, name = "Pending tests", balance = 10000.0,
        equity = 10000.0, freeMargin = 10000.0, leverage = 100.0
    )

    private fun order(
        price: Double = 100.0,
        symbol: String = "BTCUSDT",
        volume: Double = 0.01
    ) = Order(
        accountId = 1L, symbol = symbol, direction = OrderSide.BUY,
        type = OrderType.BUY_LIMIT, volume = volume, requestedPrice = price
    )

    private fun tick(symbol: String = "BTCUSDT", bid: Double = 99.0, ask: Double = 99.5) =
        Tick(symbol = symbol, bid = bid, ask = ask, last = (bid + ask) / 2.0)

    @Test fun wrongSymbolQuoteCannotFillPendingOrder() {
        assertTrue(engine.evaluatePendingOrder(order(), tick(symbol = "ETHUSDT"), account) is ExecutionResult.Error)
    }

    @Test fun invalidBidAskCannotFillPendingOrder() {
        assertTrue(engine.evaluatePendingOrder(order(), tick(bid = Double.NaN), account) is ExecutionResult.Error)
        assertTrue(engine.evaluatePendingOrder(order(), tick(bid = 101.0, ask = 100.0), account) is ExecutionResult.Error)
    }

    @Test fun invalidVolumeCannotFillPendingOrder() {
        assertTrue(engine.evaluatePendingOrder(order(volume = Double.NaN), tick(), account) is ExecutionResult.Error)
    }

    @Test fun untriggeredBuyLimitRemainsPending() {
        assertNull(engine.evaluatePendingOrder(order(price = 90.0), tick(), account))
    }

    @Test fun triggeredBuyLimitCanFillWithVerifiedQuote() {
        val result = engine.evaluatePendingOrder(order(price = 100.0), tick(), account)
        assertTrue("A triggered and valid buy limit must fill: $result", result is ExecutionResult.Success)
    }
}
