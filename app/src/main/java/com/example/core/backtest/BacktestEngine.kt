package com.example.core.backtest

import com.example.core.execution.*
import com.example.core.market.DataIntegrityValidator
import com.example.core.market.DefaultSymbols
import com.example.core.model.*
import com.example.core.risk.RiskEngine
import com.example.core.statistics.StatisticsCalculator
import com.example.core.strategy.SignalAction
import com.example.core.strategy.Strategy
import com.example.core.strategy.StrategyContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

enum class BacktestProgressStage(
    val stepNumber: Int,
    val totalSteps: Int,
    val descriptionAr: String,
    val descriptionEn: String
) {
    PREPARING_DATA(1, 5, "تجهيز وفحص بيانات الشموع", "Preparing data"),
    CALCULATING_INDICATORS(2, 5, "حساب المؤشرات الفنية", "Calculating indicators"),
    RUNNING_STRATEGY(3, 5, "تنفيذ قواعد الاستراتيجية بار-تلو-بار", "Running strategy"),
    CALCULATING_TRADES(4, 5, "تسجيل الصفقات وتقييم الأوامر", "Calculating trades"),
    CALCULATING_STATISTICS(5, 5, "استخراج الإحصاءات ومنحنى رأس المال", "Calculating statistics"),
    COMPLETED(5, 5, "اكتمل الاختبار بنجاح", "Completed"),
    CANCELLED(0, 5, "تم إلغاء الاختبار بأمان", "Cancelled"),
    FAILED(0, 5, "فشل الاختبار", "Failed")
}

data class BacktestConfig(
    val strategy: Strategy,
    val parameters: Map<String, Any> = strategy.defaultParameters,
    val symbol: String,
    val timeframe: Timeframe,
    val startTime: Long? = null,
    val endTime: Long? = null,
    val initialBalance: Double = 50.0,
    val leverage: Double = 100.0,
    val positionSizingMode: PositionSizingMode = PositionSizingMode.FIXED_LOT,
    val riskPercentage: Double = 1.0,
    val fixedLot: Double = 0.01,
    val fixedRiskAmount: Double = 5.0,
    val spreadPips: Double = 1.5,
    val slippagePips: Double = 0.2,
    val commissionPerLot: Double = 5.0,
    val swapPerLotDaily: Double = 1.0,
    val allowMultiplePositions: Boolean = false,
    val allowLong: Boolean = true,
    val allowShort: Boolean = true,
    // Backward-compatibility properties
    val fixedLotSize: Double = fixedLot,
    val useFixedLot: Boolean = (positionSizingMode == PositionSizingMode.FIXED_LOT)
) {
    fun validate(): Result<Unit> {
        if (initialBalance <= 0) return Result.failure(IllegalArgumentException("Initial balance must be positive"))
        if (leverage <= 0) return Result.failure(IllegalArgumentException("Leverage must be positive"))
        if (spreadPips < 0) return Result.failure(IllegalArgumentException("Spread cannot be negative"))
        if (slippagePips < 0) return Result.failure(IllegalArgumentException("Slippage cannot be negative"))
        if (commissionPerLot < 0) return Result.failure(IllegalArgumentException("Commission cannot be negative"))
        if (swapPerLotDaily < 0) return Result.failure(IllegalArgumentException("Swap cannot be negative"))
        when (positionSizingMode) {
            PositionSizingMode.FIXED_LOT -> {
                if (fixedLot <= 0) return Result.failure(IllegalArgumentException("Fixed lot size must be positive"))
            }
            PositionSizingMode.RISK_PERCENTAGE -> {
                if (riskPercentage <= 0.0 || riskPercentage > 100.0) {
                    return Result.failure(IllegalArgumentException("Risk percentage must be between 0.1% and 100%"))
                }
            }
            PositionSizingMode.FIXED_MONETARY_RISK -> {
                if (fixedRiskAmount <= 0.0) {
                    return Result.failure(IllegalArgumentException("Fixed monetary risk must be positive"))
                }
            }
        }
        if (!allowLong && !allowShort) {
            return Result.failure(IllegalArgumentException("At least one trading direction (Long or Short) must be enabled"))
        }
        return Result.success(Unit)
    }
}

data class BacktestResult(
    val config: BacktestConfig,
    val metrics: PerformanceMetrics,
    val equityCurve: List<EquityPoint>,
    val trades: List<TradeJournalEntry>,
    val dailySummaries: List<DailySummary> = emptyList(),
    val totalCandlesProcessed: Int,
    val run: BacktestRun? = null
)

class BacktestEngine(
    private val executionEngine: ExecutionEngine = ExecutionEngine(),
    private val riskEngine: RiskEngine = RiskEngine()
) {

    suspend fun runBacktest(
        candles: List<Candle>,
        config: BacktestConfig,
        onProgress: ((BacktestProgressStage, Float) -> Unit)? = null
    ): BacktestResult = withContext(Dispatchers.Default) {
        config.validate().getOrThrow()
        // Each backtest must honor its own execution cost settings rather than
        // silently using the ExecutionEngine's unrelated default values.
        val runExecutionEngine = ExecutionEngine(
            executionEngine.config.copy(
                slippagePips = config.slippagePips,
                defaultCommissionPerLot = config.commissionPerLot,
                swapPerLotDaily = config.swapPerLotDaily
            )
        )
        val startedAt = System.currentTimeMillis()

        onProgress?.invoke(BacktestProgressStage.PREPARING_DATA, 0.05f)

        // 1. Filter by date range if specified
        val rangeFiltered = candles.filter { c ->
            (config.startTime == null || c.openTime >= config.startTime) &&
            (config.endTime == null || c.closeTime <= config.endTime)
        }

        // 2. Validate, deduplicate, and sort chronologically (Strict Zero-Lookahead)
        val cleanCandles = DataIntegrityValidator.sanitizeCandles(rangeFiltered)

        if (cleanCandles.size < 15) {
            val emptyMetrics = StatisticsCalculator.calculate(config.initialBalance, emptyList())
            onProgress?.invoke(BacktestProgressStage.COMPLETED, 1.0f)
            val emptyRun = BacktestRun(
                strategyId = config.strategy.id,
                strategyName = config.strategy.name,
                symbol = config.symbol,
                timeframe = config.timeframe,
                startTime = cleanCandles.firstOrNull()?.openTime ?: startedAt,
                endTime = cleanCandles.lastOrNull()?.closeTime ?: startedAt,
                initialBalance = config.initialBalance,
                finalBalance = config.initialBalance,
                netProfit = 0.0,
                returnPercentage = 0.0,
                totalTrades = 0,
                winningTrades = 0,
                losingTrades = 0,
                maxDrawdown = 0.0,
                maxDrawdownPercentage = 0.0,
                profitFactor = null,
                winRate = 0.0,
                expectancy = null,
                status = BacktestRunStatus.COMPLETED,
                startedAt = startedAt,
                completedAt = System.currentTimeMillis()
            )
            return@withContext BacktestResult(
                config = config,
                metrics = emptyMetrics,
                equityCurve = emptyList(),
                trades = emptyList(),
                dailySummaries = emptyList(),
                totalCandlesProcessed = cleanCandles.size,
                run = emptyRun
            )
        }

        onProgress?.invoke(BacktestProgressStage.CALCULATING_INDICATORS, 0.20f)
        ensureActive()

        var virtualBalance = config.initialBalance
        val openPositions = mutableListOf<Position>()
        val pendingOrders = mutableListOf<Order>()
        val closedTrades = mutableListOf<TradeJournalEntry>()
        val equityPoints = mutableListOf<EquityPoint>()

        var highWatermark = config.initialBalance
        equityPoints.add(
            EquityPoint(
                timestamp = cleanCandles.first().openTime - 1000,
                balance = virtualBalance,
                equity = virtualBalance,
                drawdown = 0.0,
                highWatermark = highWatermark
            )
        )

        val symInfo = DefaultSymbols.getSymbol(config.symbol)
        var nextPositionId = 1L
        var nextOrderId = 1L

        onProgress?.invoke(BacktestProgressStage.RUNNING_STRATEGY, 0.35f)

        val total = cleanCandles.size
        val warmupPeriod = 15.coerceAtMost(total - 1)

        // Bar-by-bar sequential iteration (Strict zero-lookahead protection)
        for (i in warmupPeriod until total) {
            ensureActive()

            if (i % 25 == 0 || i == total - 1) {
                val ratio = 0.35f + (0.50f * ((i - warmupPeriod).toFloat() / (total - warmupPeriod).coerceAtLeast(1)))
                onProgress?.invoke(BacktestProgressStage.RUNNING_STRATEGY, ratio)
            }

            val currentCandle = cleanCandles[i]
            // STRICT HISTORICAL DATA BOUNDARY: Strategy can ONLY see candles up to i (<= current replay time)
            val historicalCandlesSoFar = cleanCandles.subList(0, i + 1)

            val halfSpread = (config.spreadPips * symInfo.pipSize) / 2.0
            val tick = Tick(
                symbol = config.symbol,
                bid = currentCandle.close - halfSpread,
                ask = currentCandle.close + halfSpread,
                last = currentCandle.close,
                // Tick prices are derived from the completed bar close.
                // Never timestamp them at the bar open (lookahead).
                timestamp = currentCandle.closeTime,
                source = "BACKTEST"
            )

            // Step 1: Evaluate pending orders against current bar extremes
            if (pendingOrders.isNotEmpty()) {
                val pendingIterator = pendingOrders.iterator()
                while (pendingIterator.hasNext()) {
                    val order = pendingIterator.next()
                    val isTriggered = when (order.type) {
                        OrderType.BUY_LIMIT -> currentCandle.low <= order.requestedPrice
                        OrderType.SELL_LIMIT -> currentCandle.high >= order.requestedPrice
                        OrderType.BUY_STOP -> currentCandle.high >= order.requestedPrice
                        OrderType.SELL_STOP -> currentCandle.low <= order.requestedPrice
                        else -> false
                    }

                    if (isTriggered) {
                        val fillPrice = order.requestedPrice
                        val requiredMargin = (order.volume * symInfo.contractSize * fillPrice) / config.leverage
                        val currentFreeMargin = maxOf(0.0, (virtualBalance + openPositions.sumOf { it.profitLoss }) - openPositions.sumOf { it.margin })

                        if (requiredMargin <= currentFreeMargin) {
                            val newPos = Position(
                                id = nextPositionId++,
                                accountId = 999,
                                symbol = config.symbol,
                                side = if (order.direction == OrderSide.BUY) PositionSide.BUY else PositionSide.SELL,
                                volume = order.volume,
                                entryPrice = fillPrice,
                                currentPrice = fillPrice,
                                stopLoss = order.stopLoss,
                                takeProfit = order.takeProfit,
                                openTime = currentCandle.openTime,
                                margin = requiredMargin,
                                strategyId = config.strategy.id,
                                mode = "BACKTEST"
                            )
                            openPositions.add(newPos)
                        }
                        pendingIterator.remove()
                    }
                }
            }

            // Step 2: Evaluate open positions against current bar extremes
            // DETERMINISTIC CONSERVATIVE INTRABAR RISK POLICY:
            // If both SL and TP are touched inside the same bar: Stop Loss executes first.
            val posIterator = openPositions.iterator()
            while (posIterator.hasNext()) {
                val pos = posIterator.next()
                when (val eval = runExecutionEngine.evaluatePositionOnCandle(pos, currentCandle)) {
                    is PositionEvaluation.TriggerClose -> {
                        val (trade, _) = runExecutionEngine.closePosition(
                            position = pos,
                            exitPrice = eval.exitPrice,
                            exitReason = eval.exitReason,
                            closeTime = currentCandle.openTime + (config.timeframe.minutes * 60000L)
                        )
                        closedTrades.add(trade.copy(mode = "BACKTEST"))
                        virtualBalance += trade.netProfitLoss
                        posIterator.remove()
                    }
                    is PositionEvaluation.KeepOpen -> {
                        // Check trailing stop update
                        val trailingSl = runExecutionEngine.calculateTrailingStopUpdate(pos, tick)
                        val updatedPos = if (trailingSl != null) {
                            eval.updatedPosition.copy(stopLoss = trailingSl)
                        } else {
                            eval.updatedPosition
                        }

                        val index = openPositions.indexOf(pos)
                        if (index != -1) {
                            openPositions[index] = updatedPos
                        }
                    }
                }
            }

            // Step 3: Floating equity, margin, and drawdown calculation
            val floatingPl = openPositions.sumOf { it.profitLoss }
            val usedMargin = openPositions.sumOf { it.margin }
            val currentEquity = virtualBalance + floatingPl
            val freeMargin = maxOf(0.0, currentEquity - usedMargin)
            val marginLevel = VirtualAccount.computeMarginLevel(currentEquity, usedMargin)

            if (currentEquity > highWatermark) {
                highWatermark = currentEquity
            }
            val currentDrawdown = highWatermark - currentEquity

            equityPoints.add(
                EquityPoint(
                    timestamp = currentCandle.closeTime,
                    balance = virtualBalance,
                    equity = currentEquity,
                    drawdown = currentDrawdown,
                    highWatermark = highWatermark
                )
            )

            // Step 4: Build StrategyContext strictly from data <= current bar
            val virtualAccountState = VirtualAccount(
                id = 999,
                name = "Backtest Account",
                initialBalance = config.initialBalance,
                balance = virtualBalance,
                equity = currentEquity,
                margin = usedMargin,
                freeMargin = freeMargin,
                marginLevel = marginLevel,
                leverage = config.leverage,
                mode = AccountMode.BACKTEST
            )

            val context = StrategyContext(
                symbol = config.symbol,
                timeframe = config.timeframe,
                currentCandle = currentCandle,
                historicalCandles = historicalCandlesSoFar,
                openPositions = openPositions.toList(),
                account = virtualAccountState,
                latestTick = tick
            )

            // Step 5: Execute Strategy Logic
            val signal = config.strategy.onCandle(context, config.parameters)

            when (signal.action) {
                SignalAction.CLOSE -> {
                    val itClose = openPositions.iterator()
                    while (itClose.hasNext()) {
                        val pos = itClose.next()
                        val (trade, _) = runExecutionEngine.closePosition(
                            position = pos,
                            exitPrice = currentCandle.close,
                            exitReason = ExitReason.STRATEGY_CLOSE,
                            closeTime = currentCandle.closeTime
                        )
                        closedTrades.add(trade.copy(mode = "BACKTEST"))
                        virtualBalance += trade.netProfitLoss
                        itClose.remove()
                    }
                }
                SignalAction.MODIFY -> {
                    if (signal.stopLoss != null || signal.takeProfit != null) {
                        for (idx in openPositions.indices) {
                            val pos = openPositions[idx]
                            openPositions[idx] = pos.copy(
                                stopLoss = signal.stopLoss ?: pos.stopLoss,
                                takeProfit = signal.takeProfit ?: pos.takeProfit
                            )
                        }
                    }
                }
                SignalAction.BUY, SignalAction.SELL -> {
                    val isBuy = signal.action == SignalAction.BUY
                    val isAllowed = (isBuy && config.allowLong) || (!isBuy && config.allowShort)
                    val canOpen = isAllowed && (config.allowMultiplePositions || openPositions.isEmpty())

                    if (canOpen) {
                        val side = signal.direction ?: if (isBuy) OrderSide.BUY else OrderSide.SELL

                        val lotSize = when (config.positionSizingMode) {
                            PositionSizingMode.FIXED_LOT -> {
                                (signal.suggestedVolume ?: config.fixedLot).coerceIn(symInfo.minLot, symInfo.maxLot)
                            }
                            PositionSizingMode.RISK_PERCENTAGE -> {
                                val slDistancePips = if (signal.stopLoss != null) {
                                    kotlin.math.abs(currentCandle.close - signal.stopLoss) / symInfo.pipSize
                                } else 25.0
                                riskEngine.calculateSuggestedLot(virtualAccountState, config.symbol, config.riskPercentage, slDistancePips)
                            }
                            PositionSizingMode.FIXED_MONETARY_RISK -> {
                                val slDistancePips = if (signal.stopLoss != null) {
                                    kotlin.math.abs(currentCandle.close - signal.stopLoss) / symInfo.pipSize
                                } else 25.0
                                riskEngine.calculateSuggestedLotFromFixedRiskAmount(virtualAccountState, config.symbol, config.fixedRiskAmount, slDistancePips)
                            }
                        }

                        val requiredMargin = (lotSize * symInfo.contractSize * currentCandle.close) / config.leverage

                        // Check margin availability before execution
                        if (requiredMargin <= freeMargin) {
                            val execResult = runExecutionEngine.executeMarketOrder(
                                account = virtualAccountState,
                                symbol = config.symbol,
                                side = side,
                                volume = lotSize,
                                tick = tick,
                                stopLoss = signal.stopLoss,
                                takeProfit = signal.takeProfit,
                                strategyId = config.strategy.id,
                                mode = "BACKTEST"
                            )

                            if (execResult is ExecutionResult.Success) {
                                openPositions.add(execResult.position.copy(id = nextPositionId++))
                            }
                        }
                    }
                }
                SignalAction.HOLD -> {
                    // No-op
                }
            }
        }

        onProgress?.invoke(BacktestProgressStage.CALCULATING_TRADES, 0.88f)

        // Close remaining open positions at final candle close
        if (openPositions.isNotEmpty() && cleanCandles.isNotEmpty()) {
            val lastCandle = cleanCandles.last()
            for (pos in openPositions) {
                val (trade, _) = runExecutionEngine.closePosition(
                    position = pos,
                    exitPrice = lastCandle.close,
                    exitReason = ExitReason.MANUAL_CLOSE,
                    closeTime = lastCandle.closeTime
                )
                closedTrades.add(trade.copy(mode = "BACKTEST"))
                virtualBalance += trade.netProfitLoss
            }
            openPositions.clear()
        }

        onProgress?.invoke(BacktestProgressStage.CALCULATING_STATISTICS, 0.95f)
        ensureActive()

        val performanceMetrics = StatisticsCalculator.calculate(
            initialBalance = config.initialBalance,
            trades = closedTrades,
            currentEquity = virtualBalance
        )

        val dailySummaries = StatisticsCalculator.calculateDailySummaries(closedTrades)

        val completedAt = System.currentTimeMillis()
        val runRecord = BacktestRun(
            id = 0,
            strategyId = config.strategy.id,
            strategyName = config.strategy.name,
            symbol = config.symbol,
            timeframe = config.timeframe,
            startTime = cleanCandles.first().openTime,
            endTime = cleanCandles.last().closeTime,
            initialBalance = config.initialBalance,
            finalBalance = virtualBalance,
            netProfit = performanceMetrics.netProfit,
            returnPercentage = performanceMetrics.returnPct,
            totalTrades = performanceMetrics.totalTrades,
            winningTrades = performanceMetrics.winningTrades,
            losingTrades = performanceMetrics.losingTrades,
            maxDrawdown = performanceMetrics.maxDrawdown,
            maxDrawdownPercentage = performanceMetrics.maxDrawdownPct,
            profitFactor = performanceMetrics.profitFactor,
            winRate = performanceMetrics.winRatePct,
            expectancy = performanceMetrics.expectancy,
            status = BacktestRunStatus.COMPLETED,
            startedAt = startedAt,
            completedAt = completedAt,
            duration = completedAt - startedAt
        )

        onProgress?.invoke(BacktestProgressStage.COMPLETED, 1.0f)

        BacktestResult(
            config = config,
            metrics = performanceMetrics,
            equityCurve = equityPoints,
            trades = closedTrades,
            dailySummaries = dailySummaries,
            totalCandlesProcessed = cleanCandles.size,
            run = runRecord
        )
    }
}
