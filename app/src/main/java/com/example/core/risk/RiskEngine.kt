package com.example.core.risk

import com.example.core.market.DefaultSymbols
import com.example.core.model.*
import kotlin.math.abs

class RiskEngine {

    /**
     * Calculates margin required for a new position.
     * Margin = (Volume * ContractSize * Price) / Leverage
     */
    fun calculateMargin(
        symbol: String,
        volume: Double,
        price: Double,
        leverage: Double
    ): Double {
        val symInfo = DefaultSymbols.getSymbol(symbol)
        if (leverage <= 0.0) return 0.0
        return (volume * symInfo.contractSize * price) / leverage
    }

    /**
     * Performs comprehensive pre-trade risk analysis.
     */
    fun analyzeRisk(
        account: VirtualAccount,
        symbol: String,
        side: OrderSide,
        volume: Double,
        entryPrice: Double,
        stopLoss: Double?,
        takeProfit: Double?
    ): RiskAnalysis {
        val symInfo = DefaultSymbols.getSymbol(symbol)
        val requiredMargin = calculateMargin(symbol, volume, entryPrice, account.leverage)
        val freeMarginRemaining = account.freeMargin - requiredMargin

        val isMarginSufficient = freeMarginRemaining >= 0.0

        var potentialLoss = 0.0
        var potentialProfit = 0.0
        var errorMessage: String? = null

        if (volume <= 0.0) {
            errorMessage = "حجم اللوت غير صالح"
        } else if (!isMarginSufficient) {
            errorMessage = "الهامش الافتراضي غير كافٍ ($${String.format("%.2f", requiredMargin)} مطلوبة، المتاح $${String.format("%.2f", account.freeMargin)})"
        }

        // Validate SL / TP orientation
        if (stopLoss != null) {
            when (side) {
                OrderSide.BUY -> {
                    if (stopLoss >= entryPrice) {
                        errorMessage = "وقف الخسارة للشراء يجب أن يكون أدنى من سعر الدخول"
                    } else {
                        potentialLoss = abs(entryPrice - stopLoss) * volume * symInfo.contractSize
                    }
                }
                OrderSide.SELL -> {
                    if (stopLoss <= entryPrice) {
                        errorMessage = "وقف الخسارة للبيع يجب أن يكون أعلى من سعر الدخول"
                    } else {
                        potentialLoss = abs(stopLoss - entryPrice) * volume * symInfo.contractSize
                    }
                }
            }
        }

        if (takeProfit != null) {
            when (side) {
                OrderSide.BUY -> {
                    if (takeProfit <= entryPrice) {
                        errorMessage = "جني الأرباح للشراء يجب أن يكون أعلى من سعر الدخول"
                    } else {
                        potentialProfit = abs(takeProfit - entryPrice) * volume * symInfo.contractSize
                    }
                }
                OrderSide.SELL -> {
                    if (takeProfit >= entryPrice) {
                        errorMessage = "جني الأرباح للبيع يجب أن يكون أدنى من سعر الدخول"
                    } else {
                        potentialProfit = abs(entryPrice - takeProfit) * volume * symInfo.contractSize
                    }
                }
            }
        }

        val riskReward = if (potentialLoss > 0.0 && potentialProfit > 0.0) {
            potentialProfit / potentialLoss
        } else null

        val marginTotal = account.margin + requiredMargin
        val marginLevelAfter = if (marginTotal > 0.0) (account.equity / marginTotal) * 100.0 else 0.0
        val riskPercentage = if (account.balance > 0.0) (potentialLoss / account.balance) * 100.0 else 0.0

        return RiskAnalysis(
            suggestedLotSize = volume,
            requiredMargin = requiredMargin,
            freeMarginRemaining = maxOf(0.0, freeMarginRemaining),
            marginLevelAfterOrder = marginLevelAfter,
            potentialLoss = potentialLoss,
            potentialProfit = potentialProfit,
            isMarginSufficient = isMarginSufficient && errorMessage == null,
            riskAmount = potentialLoss,
            riskPercentage = riskPercentage,
            riskRewardRatio = riskReward,
            errorMessage = errorMessage
        )
    }

    /**
     * Calculates suggested lot size based on account balance, risk percentage, and SL distance.
     */
    fun calculateSuggestedLot(
        account: VirtualAccount,
        symbol: String,
        riskPercentage: Double,
        stopLossPips: Double
    ): Double {
        if (stopLossPips <= 0.0 || riskPercentage <= 0.0) return 0.01
        val maxRiskAmount = account.balance * (riskPercentage / 100.0)
        return calculateSuggestedLotFromFixedRiskAmount(account, symbol, maxRiskAmount, stopLossPips)
    }

    /**
     * Calculates suggested lot size based on fixed monetary risk amount and SL distance.
     */
    fun calculateSuggestedLotFromFixedRiskAmount(
        account: VirtualAccount,
        symbol: String,
        fixedRiskAmount: Double,
        stopLossPips: Double
    ): Double {
        if (stopLossPips <= 0.0 || fixedRiskAmount <= 0.0) return 0.01
        val symInfo = DefaultSymbols.getSymbol(symbol)
        val lossPerLot = stopLossPips * symInfo.pipSize * symInfo.contractSize
        if (lossPerLot <= 0.0) return symInfo.minLot

        val rawLot = fixedRiskAmount / lossPerLot
        val steppedLot = (rawLot / symInfo.lotStep).toInt() * symInfo.lotStep
        return steppedLot.coerceIn(symInfo.minLot, symInfo.maxLot)
    }
}
