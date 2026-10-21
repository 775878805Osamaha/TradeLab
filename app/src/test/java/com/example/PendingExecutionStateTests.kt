package com.example

import com.example.core.execution.ExecutionEngine
import com.example.core.execution.ExecutionResult
import com.example.core.model.*
import org.junit.Assert.*
import org.junit.Test

class PendingExecutionStateTests {
    private val engine = ExecutionEngine()
    private val account = VirtualAccount(
        id = 1L, name = "Paper", balance = 100000.0,
        equity = 100000.0, freeMargin = 100000.0
    )
    private val tick = Tick(symbol = "BTCUSDT", bid = 100.0, ask = 101.0)
    private fun order(type: OrderType = OrderType.BUY_STOP, side: OrderSide = OrderSide.BUY) = Order(
        accountId = 1L, symbol = "BTCUSDT", direction = side,
        type = type, volume = 0.01, requestedPrice = 100.0
    )

    @Test fun filledCancelledAndExpiredOrdersCannotExecuteAgain() {
        for (status in listOf(OrderStatus.FILLED, OrderStatus.CANCELLED, OrderStatus.EXPIRED, OrderStatus.REJECTED)) {
            val result = engine.evaluatePendingOrder(order().copy(status = status), tick, account)
            assertTrue("Status $status must be rejected", result is ExecutionResult.Error)
        }
    }

    @Test fun explicitOrderTypeMustMatchDirection() {
        assertTrue(engine.evaluatePendingOrder(order(OrderType.BUY_STOP, OrderSide.SELL), tick, account) is ExecutionResult.Error)
        assertTrue(engine.evaluatePendingOrder(order(OrderType.SELL_LIMIT, OrderSide.BUY), tick, account) is ExecutionResult.Error)
    }

    @Test fun nonTriggeredValidOrderDoesNotFill() {
        val waiting = order(OrderType.BUY_STOP, OrderSide.BUY).copy(requestedPrice = 120.0)
        assertNull(engine.evaluatePendingOrder(waiting, tick, account))
    }
}
