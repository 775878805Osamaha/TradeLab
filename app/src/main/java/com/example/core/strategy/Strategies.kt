package com.example.core.strategy

import com.example.core.indicators.TechnicalIndicators
import com.example.core.market.DefaultSymbols
import com.example.core.model.OrderSide
import com.example.core.model.PositionSide
import java.util.concurrent.ConcurrentHashMap

class EmaCrossoverStrategy : Strategy {
    override val id: String = "EMA_CROSSOVER"
    override val name: String = "تقاطع المتوسطات الأسية (EMA Crossover)"
    override val description: String = "استراتيجية اتجاهية تعتمد على تقاطع متوسط أسي سريع مع متوسط أسي بطيء لتوليد إشارات الدخول والخروج مع حماية الصفقات المكررة."
    override val category: StrategyCategory = StrategyCategory.TREND
    override val version: Int = 1

    override val parameterDefinitions: List<StrategyParameterDefinition> = listOf(
        StrategyParameterDefinition("fastPeriod", "المتوسط الأسي السريع", ParameterType.INT, 9, minimum = 1.0, maximum = 50.0, description = "فترة حساب المتوسط السريع"),
        StrategyParameterDefinition("slowPeriod", "المتوسط الأسي البطيء", ParameterType.INT, 21, minimum = 2.0, maximum = 200.0, description = "فترة حساب المتوسط البطيء"),
        StrategyParameterDefinition("stopLossPips", "وقف الخسارة (Pips)", ParameterType.DOUBLE, 25.0, minimum = 5.0, maximum = 500.0, description = "مسافة وقف الخسارة بالنقاظ"),
        StrategyParameterDefinition("takeProfitPips", "جني الأرباح (Pips)", ParameterType.DOUBLE, 50.0, minimum = 5.0, maximum = 1000.0, description = "مسافة جني الأرباح بالنقاط")
    )

    override val defaultParameters: Map<String, Any> = mapOf(
        "fastPeriod" to 9,
        "slowPeriod" to 21,
        "stopLossPips" to 25.0,
        "takeProfitPips" to 50.0
    )

    // Internal state: session-local and resettable
    private var lastProcessedCandleTime: Long = 0L

    override fun reset() {
        lastProcessedCandleTime = 0L
    }

    override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
        val currentCandleTime = context.currentCandle.openTime

        // Duplicate signal protection for the same candle bar
        if (currentCandleTime == lastProcessedCandleTime) {
            return Signal(action = SignalAction.HOLD)
        }

        val fastPeriod = (parameters["fastPeriod"] as? Number)?.toInt() ?: 9
        val slowPeriod = (parameters["slowPeriod"] as? Number)?.toInt() ?: 21
        val slPips = (parameters["stopLossPips"] as? Number)?.toDouble() ?: 25.0
        val tpPips = (parameters["takeProfitPips"] as? Number)?.toDouble() ?: 50.0

        val candles = context.historicalCandles
        if (candles.size < slowPeriod + 2) {
            return Signal(action = SignalAction.HOLD, reason = "بيانات غير كافية لحساب المتوسطات")
        }

        val fastEma = TechnicalIndicators.calculateEma(candles, fastPeriod)
        val slowEma = TechnicalIndicators.calculateEma(candles, slowPeriod)

        val n = candles.size - 1
        val prevFast = fastEma[n - 1]
        val currFast = fastEma[n]
        val prevSlow = slowEma[n - 1]
        val currSlow = slowEma[n]

        if (prevFast == null || currFast == null || prevSlow == null || currSlow == null) {
            return Signal(action = SignalAction.HOLD)
        }

        val symInfo = context.symbolInfo
        val currentPrice = context.currentCandle.close

        // Bullish Crossover: Fast crosses above Slow
        if (prevFast <= prevSlow && currFast > currSlow) {
            // Position-aware: avoid duplicate buy if already positioned long
            val isAlreadyLong = context.openPositions.any { it.side == PositionSide.BUY }
            if (!isAlreadyLong) {
                lastProcessedCandleTime = currentCandleTime
                val sl = currentPrice - (slPips * symInfo.pipSize)
                val tp = currentPrice + (tpPips * symInfo.pipSize)
                return Signal(
                    action = SignalAction.BUY,
                    direction = OrderSide.BUY,
                    symbol = context.symbol,
                    entryPrice = currentPrice,
                    stopLoss = sl,
                    takeProfit = tp,
                    reason = "تقاطع صعودي: EMA($fastPeriod) اخترق أعلى EMA($slowPeriod)",
                    timestamp = currentCandleTime
                )
            }
        }

        // Bearish Crossover: Fast crosses below Slow
        if (prevFast >= prevSlow && currFast < currSlow) {
            // Position-aware: avoid duplicate sell if already positioned short
            val isAlreadyShort = context.openPositions.any { it.side == PositionSide.SELL }
            if (!isAlreadyShort) {
                lastProcessedCandleTime = currentCandleTime
                val sl = currentPrice + (slPips * symInfo.pipSize)
                val tp = currentPrice - (tpPips * symInfo.pipSize)
                return Signal(
                    action = SignalAction.SELL,
                    direction = OrderSide.SELL,
                    symbol = context.symbol,
                    entryPrice = currentPrice,
                    stopLoss = sl,
                    takeProfit = tp,
                    reason = "تقاطع هبوطي: EMA($fastPeriod) كسر أدنى EMA($slowPeriod)",
                    timestamp = currentCandleTime
                )
            }
        }

        return Signal(action = SignalAction.HOLD)
    }
}

class SmaCrossoverStrategy : Strategy {
    override val id: String = "SMA_CROSSOVER"
    override val name: String = "تقاطع المتوسطات البسيطة (SMA Crossover)"
    override val description: String = "استراتيجية كلاسيكية تعتمد على المتوسطات الحسابية البسيطة لرصد تغيرات الاتجاه العام."
    override val category: StrategyCategory = StrategyCategory.TREND
    override val version: Int = 1

    override val parameterDefinitions: List<StrategyParameterDefinition> = listOf(
        StrategyParameterDefinition("fastPeriod", "المتوسط البسيط السريع", ParameterType.INT, 10, minimum = 1.0, maximum = 50.0),
        StrategyParameterDefinition("slowPeriod", "المتوسط البسيط البطيء", ParameterType.INT, 30, minimum = 2.0, maximum = 200.0),
        StrategyParameterDefinition("stopLossPips", "وقف الخسارة (Pips)", ParameterType.DOUBLE, 25.0, minimum = 5.0, maximum = 500.0),
        StrategyParameterDefinition("takeProfitPips", "جني الأرباح (Pips)", ParameterType.DOUBLE, 50.0, minimum = 5.0, maximum = 1000.0)
    )

    override val defaultParameters: Map<String, Any> = mapOf(
        "fastPeriod" to 10,
        "slowPeriod" to 30,
        "stopLossPips" to 25.0,
        "takeProfitPips" to 50.0
    )

    private var lastProcessedCandleTime: Long = 0L

    override fun reset() {
        lastProcessedCandleTime = 0L
    }

    override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
        val currentCandleTime = context.currentCandle.openTime
        if (currentCandleTime == lastProcessedCandleTime) {
            return Signal(action = SignalAction.HOLD)
        }

        val fastPeriod = (parameters["fastPeriod"] as? Number)?.toInt() ?: 10
        val slowPeriod = (parameters["slowPeriod"] as? Number)?.toInt() ?: 30
        val slPips = (parameters["stopLossPips"] as? Number)?.toDouble() ?: 25.0
        val tpPips = (parameters["takeProfitPips"] as? Number)?.toDouble() ?: 50.0

        val candles = context.historicalCandles
        if (candles.size < slowPeriod + 2) {
            return Signal(action = SignalAction.HOLD)
        }

        val fastSma = TechnicalIndicators.calculateSma(candles, fastPeriod)
        val slowSma = TechnicalIndicators.calculateSma(candles, slowPeriod)

        val n = candles.size - 1
        val prevFast = fastSma[n - 1]
        val currFast = fastSma[n]
        val prevSlow = slowSma[n - 1]
        val currSlow = slowSma[n]

        if (prevFast == null || currFast == null || prevSlow == null || currSlow == null) {
            return Signal(action = SignalAction.HOLD)
        }

        val symInfo = context.symbolInfo
        val currentPrice = context.currentCandle.close

        if (prevFast <= prevSlow && currFast > currSlow) {
            if (context.openPositions.none { it.side == PositionSide.BUY }) {
                lastProcessedCandleTime = currentCandleTime
                return Signal(
                    action = SignalAction.BUY,
                    direction = OrderSide.BUY,
                    symbol = context.symbol,
                    entryPrice = currentPrice,
                    stopLoss = currentPrice - (slPips * symInfo.pipSize),
                    takeProfit = currentPrice + (tpPips * symInfo.pipSize),
                    reason = "تقاطع صعودي: SMA($fastPeriod) اخترق أعلى SMA($slowPeriod)",
                    timestamp = currentCandleTime
                )
            }
        }

        if (prevFast >= prevSlow && currFast < currSlow) {
            if (context.openPositions.none { it.side == PositionSide.SELL }) {
                lastProcessedCandleTime = currentCandleTime
                return Signal(
                    action = SignalAction.SELL,
                    direction = OrderSide.SELL,
                    symbol = context.symbol,
                    entryPrice = currentPrice,
                    stopLoss = currentPrice + (slPips * symInfo.pipSize),
                    takeProfit = currentPrice - (tpPips * symInfo.pipSize),
                    reason = "تقاطع هبوطي: SMA($fastPeriod) كسر أدنى SMA($slowPeriod)",
                    timestamp = currentCandleTime
                )
            }
        }

        return Signal(action = SignalAction.HOLD)
    }
}

class RsiMeanReversionStrategy : Strategy {
    override val id: String = "RSI_REVERSION"
    override val name: String = "ارتداد مؤشر القوة النسبية (RSI Mean Reversion)"
    override val description: String = "استراتيجية ترصد مناطق ذروة الشراء وذروة البيع للدخول مع بوادر الارتداد السعري والعودة للمسار الطبيعي."
    override val category: StrategyCategory = StrategyCategory.MEAN_REVERSION
    override val version: Int = 1

    override val parameterDefinitions: List<StrategyParameterDefinition> = listOf(
        StrategyParameterDefinition("rsiPeriod", "فترة حساب RSI", ParameterType.INT, 14, minimum = 2.0, maximum = 50.0),
        StrategyParameterDefinition("oversoldLevel", "مستوى ذروة البيع", ParameterType.DOUBLE, 30.0, minimum = 5.0, maximum = 45.0),
        StrategyParameterDefinition("overboughtLevel", "مستوى ذروة الشراء", ParameterType.DOUBLE, 70.0, minimum = 55.0, maximum = 95.0),
        StrategyParameterDefinition("stopLossPips", "وقف الخسارة (Pips)", ParameterType.DOUBLE, 20.0, minimum = 5.0, maximum = 500.0),
        StrategyParameterDefinition("takeProfitPips", "جني الأرباح (Pips)", ParameterType.DOUBLE, 40.0, minimum = 5.0, maximum = 1000.0)
    )

    override val defaultParameters: Map<String, Any> = mapOf(
        "rsiPeriod" to 14,
        "oversoldLevel" to 30.0,
        "overboughtLevel" to 70.0,
        "stopLossPips" to 20.0,
        "takeProfitPips" to 40.0
    )

    private var lastProcessedCandleTime: Long = 0L

    override fun reset() {
        lastProcessedCandleTime = 0L
    }

    override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
        val currentCandleTime = context.currentCandle.openTime
        if (currentCandleTime == lastProcessedCandleTime) {
            return Signal(action = SignalAction.HOLD)
        }

        val rsiPeriod = (parameters["rsiPeriod"] as? Number)?.toInt() ?: 14
        val oversold = (parameters["oversoldLevel"] as? Number)?.toDouble() ?: 30.0
        val overbought = (parameters["overboughtLevel"] as? Number)?.toDouble() ?: 70.0
        val slPips = (parameters["stopLossPips"] as? Number)?.toDouble() ?: 20.0
        val tpPips = (parameters["takeProfitPips"] as? Number)?.toDouble() ?: 40.0

        val candles = context.historicalCandles
        if (candles.size < rsiPeriod + 2) return Signal(action = SignalAction.HOLD)

        val rsiValues = TechnicalIndicators.calculateRsi(candles, rsiPeriod)
        val n = candles.size - 1
        val prevRsi = rsiValues[n - 1]
        val currRsi = rsiValues[n]

        if (prevRsi == null || currRsi == null) return Signal(action = SignalAction.HOLD)

        val symInfo = context.symbolInfo
        val currentPrice = context.currentCandle.close

        // Crossed back above oversold
        if (prevRsi <= oversold && currRsi > oversold) {
            if (context.openPositions.none { it.side == PositionSide.BUY }) {
                lastProcessedCandleTime = currentCandleTime
                return Signal(
                    action = SignalAction.BUY,
                    direction = OrderSide.BUY,
                    symbol = context.symbol,
                    entryPrice = currentPrice,
                    stopLoss = currentPrice - (slPips * symInfo.pipSize),
                    takeProfit = currentPrice + (tpPips * symInfo.pipSize),
                    reason = "خروج من ذروة البيع: RSI تجاوز $oversold صعوداً",
                    timestamp = currentCandleTime
                )
            }
        }

        // Crossed back below overbought
        if (prevRsi >= overbought && currRsi < overbought) {
            if (context.openPositions.none { it.side == PositionSide.SELL }) {
                lastProcessedCandleTime = currentCandleTime
                return Signal(
                    action = SignalAction.SELL,
                    direction = OrderSide.SELL,
                    symbol = context.symbol,
                    entryPrice = currentPrice,
                    stopLoss = currentPrice + (slPips * symInfo.pipSize),
                    takeProfit = currentPrice - (tpPips * symInfo.pipSize),
                    reason = "خروج من ذروة الشراء: RSI كسر $overbought هبوطاً",
                    timestamp = currentCandleTime
                )
            }
        }

        return Signal(action = SignalAction.HOLD)
    }
}

class BollingerMeanReversionStrategy : Strategy {
    override val id: String = "BOLLINGER_REVERSION"
    override val name: String = "ارتداد خطوط بولينجر (Bollinger Bands Mean Reversion)"
    override val description: String = "شراء عند ارتداد السعر داخل الحد السفلي بعد كسره، والبيع عند ارتداد السعر داخل الحد العلوي بعد اختراقه."
    override val category: StrategyCategory = StrategyCategory.MEAN_REVERSION
    override val version: Int = 1

    override val parameterDefinitions: List<StrategyParameterDefinition> = listOf(
        StrategyParameterDefinition("period", "فترة بولينجر", ParameterType.INT, 20, minimum = 2.0, maximum = 100.0),
        StrategyParameterDefinition("stdDevMultiplier", "مضاعف الانحراف المعياري", ParameterType.DOUBLE, 2.0, minimum = 0.5, maximum = 5.0),
        StrategyParameterDefinition("stopLossPips", "وقف الخسارة (Pips)", ParameterType.DOUBLE, 20.0, minimum = 5.0, maximum = 500.0),
        StrategyParameterDefinition("takeProfitPips", "جني الأرباح (Pips)", ParameterType.DOUBLE, 40.0, minimum = 5.0, maximum = 1000.0)
    )

    override val defaultParameters: Map<String, Any> = mapOf(
        "period" to 20,
        "stdDevMultiplier" to 2.0,
        "stopLossPips" to 20.0,
        "takeProfitPips" to 40.0
    )

    private var lastProcessedCandleTime: Long = 0L

    override fun reset() {
        lastProcessedCandleTime = 0L
    }

    override fun onCandle(context: StrategyContext, parameters: Map<String, Any>): Signal {
        val currentCandleTime = context.currentCandle.openTime
        if (currentCandleTime == lastProcessedCandleTime) {
            return Signal(action = SignalAction.HOLD)
        }

        val period = (parameters["period"] as? Number)?.toInt() ?: 20
        val stdDev = (parameters["stdDevMultiplier"] as? Number)?.toDouble() ?: 2.0
        val slPips = (parameters["stopLossPips"] as? Number)?.toDouble() ?: 20.0
        val tpPips = (parameters["takeProfitPips"] as? Number)?.toDouble() ?: 40.0

        val candles = context.historicalCandles
        if (candles.size < period + 2) return Signal(action = SignalAction.HOLD)

        val bands = TechnicalIndicators.calculateBollingerBands(candles, period, stdDev)
        val n = candles.size - 1
        val prevBand = bands[n - 1]
        val currBand = bands[n]
        val prevCandle = candles[n - 1]
        val currCandle = candles[n]

        if (prevBand == null || currBand == null) return Signal(action = SignalAction.HOLD)

        val symInfo = context.symbolInfo
        val currentPrice = currCandle.close

        // Bullish: previous candle closed below lower band, current closed back above lower band
        if (prevCandle.close < prevBand.lower && currCandle.close >= currBand.lower) {
            if (context.openPositions.none { it.side == PositionSide.BUY }) {
                lastProcessedCandleTime = currentCandleTime
                return Signal(
                    action = SignalAction.BUY,
                    direction = OrderSide.BUY,
                    symbol = context.symbol,
                    entryPrice = currentPrice,
                    stopLoss = currentPrice - (slPips * symInfo.pipSize),
                    takeProfit = currentPrice + (tpPips * symInfo.pipSize),
                    reason = "ارتداد صعودي داخل الحد السفلي لبولينجر",
                    timestamp = currentCandleTime
                )
            }
        }

        // Bearish: previous candle closed above upper band, current closed back below upper band
        if (prevCandle.close > prevBand.upper && currCandle.close <= currBand.upper) {
            if (context.openPositions.none { it.side == PositionSide.SELL }) {
                lastProcessedCandleTime = currentCandleTime
                return Signal(
                    action = SignalAction.SELL,
                    direction = OrderSide.SELL,
                    symbol = context.symbol,
                    entryPrice = currentPrice,
                    stopLoss = currentPrice + (slPips * symInfo.pipSize),
                    takeProfit = currentPrice - (tpPips * symInfo.pipSize),
                    reason = "ارتداد هبوطي داخل الحد العلوي لبولينجر",
                    timestamp = currentCandleTime
                )
            }
        }

        return Signal(action = SignalAction.HOLD)
    }
}

object StrategyRegistry {
    private val strategies = ConcurrentHashMap<String, Strategy>()
    private val presets = ConcurrentHashMap<String, MutableList<StrategyPreset>>()

    init {
        resetToDefaults()
    }

    fun resetToDefaults() {
        strategies.clear()
        presets.clear()

        // Register default built-in strategies
        register(EmaCrossoverStrategy())
        register(SmaCrossoverStrategy())
        register(RsiMeanReversionStrategy())
        register(BollingerMeanReversionStrategy())

        // Register default presets
        savePreset(
            StrategyPreset(
                id = "EMA_FAST",
                strategyId = "EMA_CROSSOVER",
                name = "EMA Crossover — سريع (M5/M15)",
                description = "إعداد سريع للأطر اللحظية بفترات 5 و 13",
                parameters = mapOf("fastPeriod" to 5, "slowPeriod" to 13, "stopLossPips" to 15.0, "takeProfitPips" to 30.0),
                isDefault = false
            )
        )
        savePreset(
            StrategyPreset(
                id = "EMA_BALANCED",
                strategyId = "EMA_CROSSOVER",
                name = "EMA Crossover — متوازن (قياسي)",
                description = "الإعداد الكلاسيكي المتوازن 9 / 21",
                parameters = mapOf("fastPeriod" to 9, "slowPeriod" to 21, "stopLossPips" to 25.0, "takeProfitPips" to 50.0),
                isDefault = true
            )
        )
        savePreset(
            StrategyPreset(
                id = "EMA_SLOW",
                strategyId = "EMA_CROSSOVER",
                name = "EMA Crossover — بطيء للاتجاهات الكبرى",
                description = "فلترة قوية للاتجاه بفترات 20 و 50",
                parameters = mapOf("fastPeriod" to 20, "slowPeriod" to 50, "stopLossPips" to 40.0, "takeProfitPips" to 100.0),
                isDefault = false
            )
        )
        savePreset(
            StrategyPreset(
                id = "RSI_STANDARD",
                strategyId = "RSI_REVERSION",
                name = "RSI — قياسي 30/70",
                description = "الإعداد القياسي لمستويات التشبع 30 و 70",
                parameters = mapOf("rsiPeriod" to 14, "oversoldLevel" to 30.0, "overboughtLevel" to 70.0, "stopLossPips" to 20.0, "takeProfitPips" to 40.0),
                isDefault = true
            )
        )
        savePreset(
            StrategyPreset(
                id = "RSI_CONSERVATIVE",
                strategyId = "RSI_REVERSION",
                name = "RSI — محافظ 20/80",
                description = "مستويات تشبع قصوى نادرة الإشارات ولكن عالية الدقة",
                parameters = mapOf("rsiPeriod" to 14, "oversoldLevel" to 20.0, "overboughtLevel" to 80.0, "stopLossPips" to 15.0, "takeProfitPips" to 45.0),
                isDefault = false
            )
        )
        savePreset(
            StrategyPreset(
                id = "SMA_SWING",
                strategyId = "SMA_CROSSOVER",
                name = "SMA — سوينغ 10/30",
                description = "تقاطع بسيط للمسارات اليومية والسوينغ",
                parameters = mapOf("fastPeriod" to 10, "slowPeriod" to 30, "stopLossPips" to 30.0, "takeProfitPips" to 70.0),
                isDefault = true
            )
        )
        savePreset(
            StrategyPreset(
                id = "BOLLINGER_STD",
                strategyId = "BOLLINGER_REVERSION",
                name = "Bollinger — قياسي 20/2.0",
                description = "انحراف معياري مضاعف 2.0 مع فترة 20",
                parameters = mapOf("period" to 20, "stdDevMultiplier" to 2.0, "stopLossPips" to 20.0, "takeProfitPips" to 40.0),
                isDefault = true
            )
        )
    }

    val AVAILABLE_STRATEGIES: List<Strategy>
        get() = getAllStrategies()

    fun getAllStrategies(): List<Strategy> = strategies.values.toList()

    fun getStrategy(id: String): Strategy? {
        return strategies.values.firstOrNull { it.id.equals(id, ignoreCase = true) }
    }

    fun register(strategy: Strategy) {
        strategies[strategy.id.uppercase()] = strategy
    }

    fun unregister(id: String) {
        strategies.remove(id.uppercase())
        presets.remove(id.uppercase())
    }

    fun getPresetsForStrategy(strategyId: String): List<StrategyPreset> {
        return presets[strategyId.uppercase()] ?: emptyList()
    }

    fun savePreset(preset: StrategyPreset) {
        val list = presets.getOrPut(preset.strategyId.uppercase()) { mutableListOf() }
        list.removeAll { it.id.equals(preset.id, ignoreCase = true) }
        list.add(preset)
    }

    fun deletePreset(presetId: String) {
        for (list in presets.values) {
            list.removeAll { it.id.equals(presetId, ignoreCase = true) }
        }
    }
}
