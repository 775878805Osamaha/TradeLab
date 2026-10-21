package com.example

import com.example.core.model.*
import com.example.core.replay.HistoricalReplayEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.*
import org.junit.Test

class ReplayPendingTriggerTests {
    private val engine = HistoricalReplayEngine(CoroutineScope(Dispatchers.Unconfined + SupervisorJob()))
    private val candle = Candle(
        symbol = "BTCUSDT", timeframe = Timeframe.M15,
        openTime = 1_700_000_000_000L,
        open = 100.0, high = 110.0, low = 90.0, close = 105.0
    )

    private fun order(type: OrderType, side: OrderSide, price: Double = 100.0) = Order(
        accountId = 1L, symbol = "BTCUSDT", direction = side,
        type = type, volume = 0.01, requestedPrice = price
    )

    @Test fun genericLimitAndStopOrdersRespectSide() {
        assertTrue(engine.isPendingOrderTriggeredByCandle(order(OrderType.LIMIT, OrderSide.BUY, 95.0), candle))
        assertTrue(engine.isPendingOrderTriggeredByCandle(order(OrderType.LIMIT, OrderSide.SELL, 105.0), candle))
        assertTrue(engine.isPendingOrderTriggeredByCandle(order(OrderType.STOP, OrderSide.BUY, 105.0), candle))
        assertTrue(engine.isPendingOrderTriggeredByCandle(order(OrderType.STOP, OrderSide.SELL, 95.0), candle))
        assertFalse(engine.isPendingOrderTriggeredByCandle(order(OrderType.LIMIT, OrderSide.BUY, 85.0), candle))
        assertFalse(engine.isPendingOrderTriggeredByCandle(order(OrderType.STOP, OrderSide.SELL, 85.0), candle))
    }

    @Test fun rejectsInactiveOrContradictoryOrders() {
        val pending = order(OrderType.BUY_LIMIT, OrderSide.BUY, 95.0)
        assertFalse(engine.isPendingOrderTriggeredByCandle(pending.copy(status = OrderStatus.FILLED), candle))
        assertFalse(engine.isPendingOrderTriggeredByCandle(pending.copy(status = OrderStatus.CANCELLED), candle))
        assertFalse(engine.isPendingOrderTriggeredByCandle(pending.copy(direction = OrderSide.SELL), candle))
        assertFalse(engine.isPendingOrderTriggeredByCandle(pending.copy(volume = Double.NaN), candle))
        assertFalse(engine.isPendingOrderTriggeredByCandle(pending.copy(symbol = "ETHUSDT"), candle))
    }

    @Test fun rejectsMalformedCandleAndInvalidRequestedPrice() {
        val pending = order(OrderType.SELL_STOP, OrderSide.SELL, 95.0)
        assertFalse(engine.isPendingOrderTriggeredByCandle(pending, candle.copy(close = 120.0)))
        assertFalse(engine.isPendingOrderTriggeredByCandle(pending, candle.copy(open = Double.NaN)))
        assertFalse(engine.isPendingOrderTriggeredByCandle(pending, candle.copy(low = -1.0)))
        assertFalse(engine.isPendingOrderTriggeredByCandle(pending.copy(requestedPrice = Double.POSITIVE_INFINITY), candle))
    }
}
