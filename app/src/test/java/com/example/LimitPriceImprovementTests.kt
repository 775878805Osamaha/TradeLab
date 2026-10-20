package com.example

import com.example.core.execution.*
import com.example.core.model.*
import org.junit.Assert.*
import org.junit.Test

class LimitPriceImprovementTests {
    private val engine = ExecutionEngine(ExecutionConfig(slippagePips = 0.0, defaultCommissionPerLot = 0.0))
    private val account = VirtualAccount(
        id = 1L, name = "Limit test", balance = 100000.0,
        equity = 100000.0, freeMargin = 100000.0, leverage = 100.0
    )

    private fun evaluate(type: OrderType, side: OrderSide, limit: Double, bid: Double, ask: Double): ExecutionResult? {
        val order = Order(accountId = 1L, symbol = "BTCUSDT", direction = side,
            type = type, volume = 0.01, requestedPrice = limit)
        val tick = Tick(symbol = "BTCUSDT", bid = bid, ask = ask)
        return engine.evaluatePendingOrder(order, tick, account)
    }

    @Test fun buyLimitReceivesBetterAskWhenMarketGapsLower() {
        val result = evaluate(OrderType.BUY_LIMIT, OrderSide.BUY, 100.0, 94.0, 95.0)
        assertTrue(result is ExecutionResult.Success)
        assertEquals(95.0, (result as ExecutionResult.Success).executedPrice, 0.0001)
    }

    @Test fun sellLimitReceivesBetterBidWhenMarketGapsHigher() {
        val result = evaluate(OrderType.SELL_LIMIT, OrderSide.SELL, 100.0, 105.0, 106.0)
        assertTrue(result is ExecutionResult.Success)
        assertEquals(105.0, (result as ExecutionResult.Success).executedPrice, 0.0001)
    }

    @Test fun genericLimitAlsoReceivesPriceImprovement() {
        val buy = evaluate(OrderType.LIMIT, OrderSide.BUY, 100.0, 97.0, 98.0)
        val sell = evaluate(OrderType.LIMIT, OrderSide.SELL, 100.0, 102.0, 103.0)
        assertEquals(98.0, (buy as ExecutionResult.Success).executedPrice, 0.0001)
        assertEquals(102.0, (sell as ExecutionResult.Success).executedPrice, 0.0001)
    }

    @Test fun untriggeredLimitStaysPending() {
        assertNull(evaluate(OrderType.BUY_LIMIT, OrderSide.BUY, 90.0, 99.0, 99.5))
    }
}
