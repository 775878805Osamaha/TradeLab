package com.example.core.execution

import com.example.core.market.DefaultSymbols
import com.example.core.model.OrderSide
import kotlin.math.abs
import kotlin.math.floor

/**
 * Pure, non-executing position risk estimator for USD-quoted instruments.
 * The quote currency of USDJPY is JPY, so conversion uses the entry price.
 * These figures are estimates; actual fills include spread, slippage and fees.
 */
object TradeRiskCalculator {
    data class Estimate(
        val entryPrice: Double,
        val stopLoss: Double,
        val takeProfit: Double?,
        val volumeLots: Double,
        val stopDistance: Double,
        val riskUsd: Double,
        val rewardUsd: Double?,
        val rewardRiskRatio: Double?,
        val riskPercentOfEquity: Double?,
        val maximumLotsForRisk: Double?
    )

    fun estimate(
        symbol: String,
        side: OrderSide,
        entryPrice: Double,
        stopLoss: Double,
        takeProfit: Double?,
        volumeLots: Double,
        equityUsd: Double? = null,
        targetRiskPercent: Double? = null
    ): Estimate? {
        val info = DefaultSymbols.SYMBOLS.firstOrNull {
            it.symbol.equals(symbol, true) ||
                (symbol.equals("BTCUSD", true) && it.symbol == "BTCUSDT") ||
                (symbol.equals("ETHUSD", true) && it.symbol == "ETHUSDT")
        } ?: return null
        if (!entryPrice.isFinite() || entryPrice <= 0.0 ||
            !stopLoss.isFinite() || stopLoss <= 0.0 ||
            !volumeLots.isFinite() || volumeLots <= 0.0 ||
            volumeLots < info.minLot || volumeLots > info.maxLot ||
            kotlin.math.abs(volumeLots / info.lotStep -
                kotlin.math.round(volumeLots / info.lotStep)) > 1e-6 ||
            (takeProfit != null && (!takeProfit.isFinite() || takeProfit <= 0.0)) ||
            (equityUsd != null && (!equityUsd.isFinite() || equityUsd <= 0.0)) ||
            (targetRiskPercent != null && (!targetRiskPercent.isFinite() ||
                targetRiskPercent <= 0.0 || targetRiskPercent > 100.0))) return null

        val correctStop = if (side == OrderSide.BUY) stopLoss < entryPrice else stopLoss > entryPrice
        val correctTarget = takeProfit == null ||
            if (side == OrderSide.BUY) takeProfit > entryPrice else takeProfit < entryPrice
        if (!correctStop || !correctTarget) return null

        // USDJPY contract value is in JPY; convert using the entry quote.
        val conversion = if (info.symbol == "USDJPY") 1.0 / entryPrice else 1.0
        val distance = abs(entryPrice - stopLoss)
        val riskPerLot = distance * info.contractSize * conversion
        val risk = riskPerLot * volumeLots
        val reward = takeProfit?.let { abs(it - entryPrice) * info.contractSize * conversion * volumeLots }
        if (!risk.isFinite() || risk <= 0.0 || (reward != null && !reward.isFinite())) return null

        val maxLots = if (equityUsd != null && targetRiskPercent != null) {
            val raw = (equityUsd * targetRiskPercent / 100.0) / riskPerLot
            if (!raw.isFinite()) null else {
                val steps = floor((raw + 1e-9) / info.lotStep)
                (steps * info.lotStep).coerceAtMost(info.maxLot).takeIf { it >= info.minLot }
            }
        } else null
        return Estimate(entryPrice, stopLoss, takeProfit, volumeLots, distance, risk, reward,
            reward?.div(risk), equityUsd?.let { risk / it * 100.0 }, maxLots)
    }
}
