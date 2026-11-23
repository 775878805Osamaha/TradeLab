package com.example.core.strategy

import com.example.core.model.OrderSide
import com.example.core.model.PositionSide

/**
 * An educational baseline for validating the historical tester end-to-end.
 * Uses only current/past *closed* candles; never inspects future prices.
 * It is not a profitability claim or a recommended trading system.
 */
class SmaCrossoverExample : Strategy {
    override val id = "SMA_CROSSOVER_EXAMPLE"
    override val name = "تقاطع المتوسطات SMA — نموذج تعليمي"
    override val description = "إشارة عند تقاطع متوسطين بسيطين باستخدام الشموع التاريخية المكتملة فقط؛ للاختبار والتعلّم."
    override val category = StrategyCategory.TREND
    override val defaultParameters: Map<String, Any> = mapOf(
        "fastPeriod" to 9,
        "slowPeriod" to 21,
        "stopLossPercent" to 0.35,
        "takeProfitPercent" to 0.7
    )

    override val parameterDefinitions = listOf(
        StrategyParameterDefinition("fastPeriod", "المتوسط السريع", ParameterType.INT, 9,
            minimum = 2.0, maximum = 100.0),
        StrategyParameterDefinition("slowPeriod", "المتوسط البطيء", ParameterType.INT, 21,
            minimum = 3.0, maximum = 200.0),
        StrategyParameterDefinition("stopLossPercent", "وقف الخسارة %", ParameterType.DOUBLE, 0.35,
            minimum = 0.05, maximum = 10.0),
        StrategyParameterDefinition("takeProfitPercent", "جني الربح %", ParameterType.DOUBLE, 0.7,
            minimum = 0.05, maximum = 20.0)
    )

    override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
        val fast = (parameters["fastPeriod"] as? Number)?.toInt() ?: 9
        val slow = (parameters["slowPeriod"] as? Number)?.toInt() ?: 21
        val slPct = (parameters["stopLossPercent"] as? Number)?.toDouble() ?: 0.35
        val tpPct = (parameters["takeProfitPercent"] as? Number)?.toDouble() ?: 0.7
        val bars = context.historicalCandles
        if (fast < 2 || slow <= fast || slow > 200 || bars.size < slow + 1 ||
            !slPct.isFinite() || slPct !in 0.05..10.0 ||
            !tpPct.isFinite() || tpPct !in 0.05..20.0) return Signal(SignalAction.HOLD)

        // The previous window excludes the current bar; current includes it.
        fun sma(end: Int, length: Int): Double =
            (end - length until end).sumOf { bars[it].close } / length

        val end = bars.size
        val prevFast = sma(end - 1, fast)
        val prevSlow = sma(end - 1, slow)
        val nowFast = sma(end, fast)
        val nowSlow = sma(end, slow)
        val crossUp = prevFast <= prevSlow && nowFast > nowSlow
        val crossDown = prevFast >= prevSlow && nowFast < nowSlow
        val price = context.currentCandle.close
        if (!price.isFinite() || price <= 0.0) return Signal(SignalAction.HOLD)

        if (crossUp) {
            if (context.openPositions.any { it.side == PositionSide.SELL })
                return Signal(SignalAction.CLOSE, reason = "تقاطع معاكس صاعد")
            if (context.openPositions.isEmpty()) return Signal(
                action = SignalAction.BUY, direction = OrderSide.BUY,
                stopLoss = price * (1 - slPct / 100.0),
                takeProfit = price * (1 + tpPct / 100.0),
                reason = "تقاطع SMA صاعد مكتمل"
            )
        }
        if (crossDown) {
            if (context.openPositions.any { it.side == PositionSide.BUY })
                return Signal(SignalAction.CLOSE, reason = "تقاطع معاكس هابط")
            if (context.openPositions.isEmpty()) return Signal(
                action = SignalAction.SELL, direction = OrderSide.SELL,
                stopLoss = price * (1 + slPct / 100.0),
                takeProfit = price * (1 - tpPct / 100.0),
                reason = "تقاطع SMA هابط مكتمل"
            )
        }
        return Signal(SignalAction.HOLD)
    }
}
