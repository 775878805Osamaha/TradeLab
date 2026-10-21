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
        // NaN silently bypasses ordinary numeric comparisons and can corrupt
        // equity, margin and statistics. Reject non-finite inputs up front.
        if (!initialBalance.isFinite() || initialBalance <= 0.0) return Result.failure(IllegalArgumentException("Initial balance must be finite and positive"))
        if (!leverage.isFinite() || leverage <= 0.0) return Result.failure(IllegalArgumentException("Leverage must be finite and positive"))
        if (!spreadPips.isFinite() || spreadPips < 0.0) return Result.failure(IllegalArgumentException("Spread must be finite and non-negative"))
        if (!slippagePips.isFinite() || slippagePips < 0.0) return Result.failure(IllegalArgumentException("Slippage must be finite and non-negative"))
        if (!commissionPerLot.isFinite() || commissionPerLot < 0.0) return Result.failure(IllegalArgumentException("Commission must be finite and non-negative"))
        if (!swapPerLotDaily.isFinite() || swapPerLotDaily < 0.0) return Result.failure(IllegalArgumentException("Swap must be finite and non-negative"))
        if (startTime != null && endTime != null && startTime > endTime) return Result.failure(IllegalArgumentException("Start time must not exceed end time"))
        when (positionSizingMode) {
            PositionSizingMode.FIXED_LOT -> {
                if (!fixedLot.isFinite() || fixedLot <= 0.0) return Result.failure(IllegalArgumentException("Fixed lot size must be positive"))
            }
            PositionSizingMode.RISK_PERCENTAGE -> {
                if (!riskPercentage.isFinite() || riskPercentage <= 0.0 || riskPercentage > 100.0) {
                    return Result.failure(IllegalArgumentException("Risk percentage must be between 0.1% and 100%"))
                }
            }
            PositionSizingMode.FIXED_MONETARY_RISK -> {
                if (!fixedRiskAmount.isFinite() || fixedRiskAmount <= 0.0) {
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
        // Reject mixed-symbol or mixed-timeframe input even when date filtering
        // would otherwise hide invalid candles.
        require(candles.all { it.symbol.equals(config.symbol, ignoreCase = true) && it.timeframe == config.timeframe }) {
            "Historical candles must match the backtest symbol and timeframe"
        }
        val rangeFiltered = candles.filter { c ->
            (config.startTime == null || c.openTime >= config.startTime) &&
            (config.endTime == null || c.closeTime <= config.endTime)
        }

        // 2. Validate, deduplicate, and sort chronologically (Strict Zero-Lookahead)
        val cleanCandles = DataIntegrityValidator.sanitizeCandles(rangeFiltered)

        if (cleanCandles.size <= 15) {
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
        val closedTrades = mutableListOf<TradeJournalEntry>()
        val equityPoints = mutableListOf<EquityPoint>()

        var highWatermark = config.initialBalance
        equityPoints.add(
            EquityPoint(
                // Never fabricate a timestamp before the first available bar.
                timestamp = cleanCandles.first().openTime,
                balance = virtualBalance,
                equity = virtualBalance,
                drawdown = 0.0,
                highWatermark = highWatermark
            )
        )

        val symInfo = DefaultSymbols.getSymbol(config.symbol)
        var nextPositionId = 1L

        onProgress?.invoke(BacktestProgressStage.RUNNING_STRATEGY, 0.35f)

        val total = cleanCandles.size
        val warmupPeriod = 15

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
            // The configured spread cannot produce a non-positive bid.
            require(halfSpread.isFinite() && currentCandle.low > halfSpread) {
                "Configured spread exceeds the available candle price"
            }
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

            // Pending orders are not currently created by the strategy API.
            // Do not simulate fills from an unreachable queue: future order
            // placement must be integrated with the execution engine first.

            // Step 2: Evaluate open positions against current bar extremes
            // DETERMINISTIC CONSERVATIVE INTRABAR RISK POLICY:
            // If both SL and TP are touched inside the same bar: Stop Loss executes first.
            val posIterator = openPositions.listIterator()
            while (posIterator.hasNext()) {
                val pos = posIterator.next()
                // Candle OHLC represents the mid-price. A BUY exits at bid
                // and a SELL exits at ask, including intrabar SL/TP triggers.
                val exitSideAdjustment = if (pos.side == PositionSide.BUY) -halfSpread else halfSpread
                val executableCandle = currentCandle.copy(
                    open = currentCandle.open + exitSideAdjustment,
                    high = currentCandle.high + exitSideAdjustment,
                    low = currentCandle.low + exitSideAdjustment,
                    close = currentCandle.close + exitSideAdjustment
                )
                when (val eval = runExecutionEngine.evaluatePositionOnCandle(pos, executableCandle)) {
                    is PositionEvaluation.TriggerClose -> {
                        val (trade, _) = runExecutionEngine.closePosition(
                            position = pos,
                            exitPrice = eval.exitPrice,
                            exitReason = eval.exitReason,
                            closeTime = currentCandle.closeTime
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

                        // Updating through the iterator preserves iteration consistency.
                        posIterator.set(updatedPos)
                    }
                }
            }

            // The account and equity snapshot must reflect the current bar
            // after all intrabar exits have been processed.
            // Strategy actions at this close are reconciled at the next bar,
            // except for the terminal snapshot which is finalized below.
            // Step 3: Floating equity, margin, and drawdown calculation.
            // Position.profitLoss is gross mark-to-market; entry commission and
            // accrued swap are liabilities even before a position is closed.
            val currentEquity = BacktestEquityAccounting.equity(
                virtualBalance,
                openPositions.map {
                    BacktestEquityAccounting.OpenPositionValue(
                        grossProfitLoss = it.profitLoss,
                        entryCommission = it.commission,
                        accruedSwap = it.swap
                    )
                }
            )
            val usedMargin = openPositions.sumOf { it.margin }
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
                latestTick = tick,
                currentTime = currentCandle.closeTime,
                strategyParameters = config.parameters
            )

            // Step 5: Execute Strategy Logic
            val signal = config.strategy.onCandle(context, config.parameters)

            // Validate only fields used by this action. A CLOSE must not be
            // discarded because an unrelated suggestedVolume is malformed.
            if (signal.symbol != null && !signal.symbol.equals(config.symbol, ignoreCase = true)) continue
            val opensPosition = signal.action == SignalAction.BUY || signal.action == SignalAction.SELL
            val changesStops = opensPosition || signal.action == SignalAction.MODIFY
            if (opensPosition) {
                if (signal.entryPrice != null && (!signal.entryPrice.isFinite() || signal.entryPrice <= 0.0)) continue
                if (signal.suggestedVolume != null && (!signal.suggestedVolume.isFinite() || signal.suggestedVolume <= 0.0)) continue
            }
            if (changesStops) {
                if (signal.stopLoss != null && (!signal.stopLoss.isFinite() || signal.stopLoss <= 0.0)) continue
                if (signal.takeProfit != null && (!signal.takeProfit.isFinite() || signal.takeProfit <= 0.0)) continue
            }

            when (signal.action) {
                SignalAction.CLOSE -> {
                    val itClose = openPositions.iterator()
                    while (itClose.hasNext()) {
                        val pos = itClose.next()
                        val (trade, _) = runExecutionEngine.closePosition(
                            position = pos,
                            // BUY liquidates at bid; SELL liquidates at ask.
                            exitPrice = if (pos.side == PositionSide.BUY) tick.bid else tick.ask,
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
                    val side = if (isBuy) OrderSide.BUY else OrderSide.SELL
                    // The signal action is authoritative; a contradictory optional
                    // direction must never silently open the opposite position.
                    val isAllowed = (isBuy && config.allowLong) || (!isBuy && config.allowShort)
                    // Do not open a position on the final candle only to
                    // force-liquidate it at the same close (artificial loss).
                    val canOpen = isAllowed && i < total - 1 &&
                        (config.allowMultiplePositions || openPositions.isEmpty())

                    if (canOpen) {
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

                        if (!lotSize.isFinite() || lotSize <= 0.0) continue
                        // The execution engine is the source of truth for
                        // fill price, slippage, margin and order validation.
                        // Do not duplicate an approximate margin check here.
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
                SignalAction.HOLD -> {
                    // No-op
                }
            }

            // Record the state AFTER strategy execution at this candle close.
            // This captures entry commission immediately, and realizes CLOSE
            // signals on the same bar rather than one candle late.
            val settledEquity = BacktestEquityAccounting.equity(
                virtualBalance,
                openPositions.map {
                    BacktestEquityAccounting.OpenPositionValue(
                        grossProfitLoss = it.profitLoss,
                        entryCommission = it.commission,
                        accruedSwap = it.swap
                    )
                }
            )
            highWatermark = maxOf(highWatermark, settledEquity)
            equityPoints[equityPoints.lastIndex] = EquityPoint(
                timestamp = currentCandle.closeTime,
                balance = virtualBalance,
                equity = settledEquity,
                drawdown = highWatermark - settledEquity,
                highWatermark = highWatermark
            )
        }

        onProgress?.invoke(BacktestProgressStage.CALCULATING_TRADES, 0.88f)

        // Close remaining open positions at final candle close
        if (openPositions.isNotEmpty() && cleanCandles.isNotEmpty()) {
            val lastCandle = cleanCandles.last()
            for (pos in openPositions) {
                val (trade, _) = runExecutionEngine.closePosition(
                    position = pos,
                    // Final forced liquidation must pay the spread too.
                    exitPrice = if (pos.side == PositionSide.BUY) {
                        lastCandle.close - (config.spreadPips * symInfo.pipSize / 2.0)
                    } else {
                        lastCandle.close + (config.spreadPips * symInfo.pipSize / 2.0)
                    },
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

        // A strategy close on the final candle can change the balance after
        // the equity snapshot was recorded; make the terminal curve accurate.
        if (equityPoints.isNotEmpty()) {
            val last = equityPoints.last()
            val terminalWatermark = maxOf(highWatermark, virtualBalance)
            equityPoints[equityPoints.lastIndex] = last.copy(
                balance = virtualBalance,
                equity = virtualBalance,
                drawdown = terminalWatermark - virtualBalance,
                highWatermark = terminalWatermark
            )
        }

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
