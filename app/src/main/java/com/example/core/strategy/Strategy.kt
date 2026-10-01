package com.example.core.strategy

import com.example.core.market.DefaultSymbols
import com.example.core.model.*

enum class SignalAction {
    BUY,
    SELL,
    HOLD,
    CLOSE,
    MODIFY
}

enum class StrategyCategory(val displayNameAr: String, val displayNameEn: String) {
    TREND("تتبع الاتجاه (Trend)", "Trend"),
    MEAN_REVERSION("الارتداد للمتوسط (Mean Reversion)", "Mean Reversion"),
    MOMENTUM("الزخم السعري (Momentum)", "Momentum"),
    CUSTOM("مخصصة (Custom)", "Custom")
}

enum class ParameterType {
    INT,
    DOUBLE,
    BOOLEAN,
    ENUM,
    STRING
}

data class StrategyParameterDefinition(
    val id: String,
    val name: String,
    val type: ParameterType,
    val defaultValue: Any,
    val minimum: Double? = null,
    val maximum: Double? = null,
    val step: Double? = null,
    val options: List<String> = emptyList(),
    val description: String = ""
)

data class StrategyPreset(
    val id: String,
    val strategyId: String,
    val name: String,
    val description: String = "",
    val parameters: Map<String, Any>,
    val riskPercentage: Double = 1.0,
    val fixedLot: Double = 0.01,
    val stopLossPips: Double? = null,
    val takeProfitPips: Double? = null,
    val isDefault: Boolean = false
)

data class ValidationError(
    val field: String,
    val message: String
)

data class StrategyValidationResult(
    val isValid: Boolean,
    val errors: List<ValidationError> = emptyList()
) {
    companion object {
        fun success() = StrategyValidationResult(isValid = true)
        fun failure(errors: List<ValidationError>) = StrategyValidationResult(isValid = false, errors = errors)
        fun failure(field: String, message: String) = StrategyValidationResult(isValid = false, errors = listOf(ValidationError(field, message)))
    }
}

object StrategyValidator {
    fun validate(strategy: Strategy, parameters: Map<String, Any>): StrategyValidationResult {
        val errors = mutableListOf<ValidationError>()
        for (def in strategy.parameterDefinitions) {
            val value = parameters[def.id] ?: def.defaultValue
            when (def.type) {
                ParameterType.INT -> {
                    val num = (value as? Number)?.toInt()
                    if (num == null) {
                        errors.add(ValidationError(def.id, "المعامل '${def.name}' يجب أن يكون رقماً صحيحاً"))
                    } else {
                        if (def.minimum != null && num < def.minimum) {
                            errors.add(ValidationError(def.id, "قيمة '${def.name}' لا يمكن أن تقل عن ${def.minimum.toInt()}"))
                        }
                        if (def.maximum != null && num > def.maximum) {
                            errors.add(ValidationError(def.id, "قيمة '${def.name}' لا يمكن أن تزيد عن ${def.maximum.toInt()}"))
                        }
                    }
                }
                ParameterType.DOUBLE -> {
                    val num = (value as? Number)?.toDouble()
                    if (num == null) {
                        errors.add(ValidationError(def.id, "المعامل '${def.name}' يجب أن يكون رقماً عشرياً"))
                    } else {
                        if (def.minimum != null && num < def.minimum) {
                            errors.add(ValidationError(def.id, "قيمة '${def.name}' لا يمكن أن تقل عن ${def.minimum}"))
                        }
                        if (def.maximum != null && num > def.maximum) {
                            errors.add(ValidationError(def.id, "قيمة '${def.name}' لا يمكن أن تزيد عن ${def.maximum}"))
                        }
                    }
                }
                ParameterType.ENUM -> {
                    val str = value.toString()
                    if (def.options.isNotEmpty() && !def.options.contains(str)) {
                        errors.add(ValidationError(def.id, "القيمة '$str' غير مدعومة للمعامل '${def.name}'"))
                    }
                }
                else -> {}
            }
        }

        // Cross-field validations for specific strategies
        if (strategy.id.contains("CROSSOVER", ignoreCase = true)) {
            val fast = (parameters["fastPeriod"] as? Number)?.toInt()
            val slow = (parameters["slowPeriod"] as? Number)?.toInt()
            if (fast != null && slow != null && fast >= slow) {
                errors.add(ValidationError("slowPeriod", "المتوسط البطيء ($slow) يجب أن يكون أكبر قطباً من المتوسط السريع ($fast)"))
            }
        }

        if (strategy.id.contains("RSI", ignoreCase = true)) {
            val oversold = (parameters["oversoldLevel"] as? Number)?.toDouble()
            val overbought = (parameters["overboughtLevel"] as? Number)?.toDouble()
            if (oversold != null && (oversold <= 0.0 || oversold >= 50.0)) {
                errors.add(ValidationError("oversoldLevel", "مستوى ذروة البيع يجب أن يكون بين 1 و 49"))
            }
            if (overbought != null && (overbought <= 50.0 || overbought >= 100.0)) {
                errors.add(ValidationError("overboughtLevel", "مستوى ذروة الشراء يجب أن يكون بين 51 و 99"))
            }
        }

        return if (errors.isEmpty()) StrategyValidationResult.success() else StrategyValidationResult.failure(errors)
    }
}

data class StrategyConfiguration(
    val id: String,
    val strategyId: String,
    val strategyVersion: Int = 1,
    val name: String,
    val symbol: String,
    val timeframe: Timeframe,
    val parameters: Map<String, Any>,
    val riskPercentage: Double = 1.0,
    val fixedLot: Double = 0.01,
    val stopLossPips: Double? = null,
    val takeProfitPips: Double? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)

data class Signal(
    val action: SignalAction,
    val direction: OrderSide? = null,
    val symbol: String? = null,
    val entryPrice: Double? = null,
    val stopLoss: Double? = null,
    val takeProfit: Double? = null,
    val suggestedVolume: Double? = null,
    val reason: String = "",
    val timestamp: Long = System.currentTimeMillis(),
    val metadata: Map<String, Any> = emptyMap()
)

data class StrategyContext(
    val symbol: String,
    val timeframe: Timeframe,
    val currentCandle: Candle,
    val historicalCandles: List<Candle>, // STRICTLY up to current candle only
    val openPositions: List<Position>,
    val account: VirtualAccount,
    val latestTick: Tick? = null,
    val pendingOrders: List<Order> = emptyList(),
    val symbolInfo: SymbolInfo = DefaultSymbols.getSymbol(symbol),
    val currentTime: Long = currentCandle.openTime,
    val strategyParameters: Map<String, Any> = emptyMap()
)

interface Strategy {
    val id: String
    val name: String
    val description: String
    val category: StrategyCategory get() = StrategyCategory.TREND
    val version: Int get() = 1
    val parameterDefinitions: List<StrategyParameterDefinition> get() = emptyList()
    val defaultParameters: Map<String, Any>

    fun onStart(context: StrategyContext) {}
    fun onCandle(context: StrategyContext, parameters: Map<String, Any> = defaultParameters): Signal
    fun onTick(context: StrategyContext, parameters: Map<String, Any> = defaultParameters): Signal? = null
    fun onPositionUpdate(context: StrategyContext, parameters: Map<String, Any> = defaultParameters) {}
    fun onStop(context: StrategyContext) {}
    fun reset() {}
}
