package com.example.core.execution

import com.example.core.market.DefaultSymbols
import com.example.core.model.*
import kotlin.math.abs
import kotlin.math.max

data class ExecutionConfig(
    val defaultCommissionPerLot: Double = 5.0, // $5 per round lot
    val slippagePips: Double = 0.2, // 0.2 pips realistic execution slippage
    val swapPerLotDaily: Double = 1.0, // $1 swap per lot
    val allowPartialFills: Boolean = false
)

sealed class ExecutionResult {
    data class Success(val position: Position, val executedPrice: Double, val commission: Double) : ExecutionResult()
    data class Closed(val trade: TradeJournalEntry, val exitPrice: Double, val netProfit: Double) : ExecutionResult()
    data class Error(val message: String) : ExecutionResult()
}

class ExecutionEngine(
    val config: ExecutionConfig = ExecutionConfig()
) {

    /**
     * Executes a virtual market order using real Bid/Ask prices with spread, slippage, and commission.
     * Enforces strict validation invariants.
     */
    fun executeMarketOrder(
        account: VirtualAccount,
        symbol: String,
        side: OrderSide,
        volume: Double,
        tick: Tick,
        stopLoss: Double?,
        takeProfit: Double?,
        strategyId: String? = null,
        mode: String = "LIVE_PAPER"
    ): ExecutionResult {
        // A market fill must never use a quote from a different instrument.
        if (!symbol.equals(tick.symbol, ignoreCase = true) &&
            !(symbol.equals("BTCUSD", ignoreCase = true) && tick.symbol.equals("BTCUSDT", ignoreCase = true)) &&
            !(symbol.equals("ETHUSD", ignoreCase = true) && tick.symbol.equals("ETHUSDT", ignoreCase = true))) {
            return ExecutionResult.Error("رمز سعر السوق لا يطابق رمز الصفقة")
        }
        if (!config.slippagePips.isFinite() || config.slippagePips < 0.0 ||
            !config.defaultCommissionPerLot.isFinite() || config.defaultCommissionPerLot < 0.0) {
            return ExecutionResult.Error("إعدادات الانزلاق السعري أو العمولة غير صالحة")
        }
        // Enforce strict order validation
        val validation = OrderValidator.validate(
            account = account,
            symbol = symbol,
            type = OrderType.MARKET,
            side = side,
            volume = volume,
            tick = tick,
            stopLoss = stopLoss,
            takeProfit = takeProfit
        )
        if (validation is OrderValidationResult.Rejected) {
            return ExecutionResult.Error(validation.message)
        }

        val symInfo = DefaultSymbols.getSymbol(symbol)

        // Calculate fill price based on side
        // BUY fills at Ask (+ slippage)
        // SELL fills at Bid (- slippage)
        val slippageOffset = config.slippagePips * symInfo.pipSize
        val executedPrice = when (side) {
            OrderSide.BUY -> tick.ask + slippageOffset
            OrderSide.SELL -> tick.bid - slippageOffset
        }

        if (!executedPrice.isFinite() || executedPrice <= 0.0) {
            return ExecutionResult.Error("سعر التنفيذ بعد الانزلاق السعري غير صالح")
        }

        // Commission
        val commission = config.defaultCommissionPerLot * volume

        // Required margin
        val margin = (volume * symInfo.contractSize * executedPrice) / account.leverage

        if (!margin.isFinite() || margin <= 0.0 || margin > account.freeMargin) {
            return ExecutionResult.Error("الهامش الافتراضي غير كافٍ لتنفيذ هذا العقد")
        }

        val positionSide = when (side) {
            OrderSide.BUY -> PositionSide.BUY
            OrderSide.SELL -> PositionSide.SELL
        }

        val position = Position(
            accountId = account.id,
            symbol = symInfo.symbol,
            side = positionSide,
            volume = volume,
            entryPrice = executedPrice,
            currentPrice = executedPrice,
            stopLoss = stopLoss,
            takeProfit = takeProfit,
            openTime = tick.timestamp,
            profitLoss = 0.0,
            swap = 0.0,
            commission = commission,
            margin = margin,
            strategyId = strategyId,
            mode = mode
        )

        return ExecutionResult.Success(position, executedPrice, commission)
    }

    /**
     * Evaluates a pending order (BUY LIMIT, SELL LIMIT, BUY STOP, SELL STOP) against the current tick.
     * If the price trigger is satisfied, executes the virtual order.
     */
    fun evaluatePendingOrder(
        order: Order,
        tick: Tick,
        account: VirtualAccount,
        mode: String = "LIVE_PAPER",
        historicalFillPrice: Double? = null
    ): ExecutionResult? {
        // Pending orders belong to exactly one paper account. Never fill an
        // order against another account's balance, margin or positions.
        if (order.accountId != account.id) {
            return ExecutionResult.Error("الأمر المعلق لا ينتمي إلى الحساب الحالي")
        }
        // Never execute an order already filled, cancelled, rejected or expired.
        // Explicit BUY/SELL order types must also agree with their direction.
        if (order.status != OrderStatus.PENDING ||
            order.type == OrderType.MARKET ||
            when (order.type) {
                OrderType.BUY_LIMIT, OrderType.BUY_STOP -> order.direction != OrderSide.BUY
                OrderType.SELL_LIMIT, OrderType.SELL_STOP -> order.direction != OrderSide.SELL
                else -> false
            }) {
            return ExecutionResult.Error("حالة الأمر المعلق أو اتجاهه غير صالح للتنفيذ")
        }
        // Never fill a pending order using another symbol's quote or invalid market data.
        if (!order.symbol.equals(tick.symbol, ignoreCase = true) ||
            !tick.bid.isFinite() || !tick.ask.isFinite() ||
            tick.bid <= 0.0 || tick.ask < tick.bid ||
            !order.requestedPrice.isFinite() || order.requestedPrice <= 0.0) {
            return ExecutionResult.Error("سعر السوق أو رمز الأمر المعلق غير صالح")
        }
        // Historical fill overrides must never be accepted by the live-paper
        // path, including when the value is NaN or infinite. Reject before
        // constructing synthetic quotes or running account validation.
        if (historicalFillPrice != null &&
            (mode != "REPLAY" || !historicalFillPrice.isFinite() || historicalFillPrice <= 0.0)) {
            return ExecutionResult.Error("سعر التنفيذ التاريخي غير صالح")
        }
        // For OHLC replay, validation must use the modeled historical entry
        // quote, not the candle-close tick. Otherwise a wick-triggered pending
        // order can be rejected because its SL/TP is compared to the wrong price.
        val sym = DefaultSymbols.getSymbol(order.symbol)
        val spread = sym.defaultSpreadPips * sym.pipSize
        val validationTick = if (historicalFillPrice != null &&
            historicalFillPrice.isFinite() && historicalFillPrice > 0.0 &&
            spread.isFinite() && spread >= 0.0) {
            if (order.direction == OrderSide.BUY) {
                tick.copy(ask = historicalFillPrice, bid = historicalFillPrice - spread)
            } else {
                tick.copy(bid = historicalFillPrice, ask = historicalFillPrice + spread)
            }
        } else tick
        if (historicalFillPrice != null &&
            (!validationTick.bid.isFinite() || validationTick.bid <= 0.0 ||
                !validationTick.ask.isFinite() || validationTick.ask < validationTick.bid)) {
            return ExecutionResult.Error("سعر تنفيذ Replay بعد احتساب السبريد غير صالح")
        }
        val validation = OrderValidator.validate(
            account = account,
            symbol = order.symbol,
            // Validate execution-time constraints at the historical fill quote.
            type = OrderType.MARKET,
            side = order.direction,
            volume = order.volume,
            tick = validationTick,
            stopLoss = order.stopLoss,
            takeProfit = order.takeProfit
        )
        if (validation is OrderValidationResult.Rejected) {
            return ExecutionResult.Error(validation.message)
        }
        // Historical overrides are only legal at an executable price consistent
        // with the order type. Reject accidental favorable stop fills and
        // unfavorable limit fills instead of silently corrupting backtests.
        if (historicalFillPrice != null) {
            val consistent = when (order.type) {
                OrderType.BUY_LIMIT -> order.direction == OrderSide.BUY && historicalFillPrice <= order.requestedPrice
                OrderType.SELL_LIMIT -> order.direction == OrderSide.SELL && historicalFillPrice >= order.requestedPrice
                OrderType.BUY_STOP -> order.direction == OrderSide.BUY && historicalFillPrice >= order.requestedPrice
                OrderType.SELL_STOP -> order.direction == OrderSide.SELL && historicalFillPrice <= order.requestedPrice
                OrderType.LIMIT -> if (order.direction == OrderSide.BUY) historicalFillPrice <= order.requestedPrice else historicalFillPrice >= order.requestedPrice
                OrderType.STOP -> if (order.direction == OrderSide.BUY) historicalFillPrice >= order.requestedPrice else historicalFillPrice <= order.requestedPrice
                else -> false
            }
            if (!consistent) return ExecutionResult.Error("سعر التنفيذ التاريخي لا يتوافق مع نوع الأمر")
        }
        val symInfo = DefaultSymbols.getSymbol(order.symbol)
        val slippageOffset = config.slippagePips * symInfo.pipSize

        val isTriggered = when (order.type) {
            OrderType.BUY_LIMIT -> tick.ask <= order.requestedPrice
            OrderType.SELL_LIMIT -> tick.bid >= order.requestedPrice
            OrderType.BUY_STOP -> tick.ask >= order.requestedPrice
            OrderType.SELL_STOP -> tick.bid <= order.requestedPrice
            OrderType.LIMIT -> if (order.direction == OrderSide.BUY) tick.ask <= order.requestedPrice else tick.bid >= order.requestedPrice
            OrderType.STOP -> if (order.direction == OrderSide.BUY) tick.ask >= order.requestedPrice else tick.bid <= order.requestedPrice
            else -> false
        }

        if (!isTriggered && historicalFillPrice == null) return null

        val executedPrice = historicalFillPrice ?: when (order.type) {
            // Limit orders can fill at the limit or a better available market quote.
            OrderType.BUY_LIMIT -> minOf(order.requestedPrice, tick.ask)
            OrderType.SELL_LIMIT -> maxOf(order.requestedPrice, tick.bid)
            OrderType.BUY_STOP -> tick.ask + slippageOffset
            OrderType.SELL_STOP -> tick.bid - slippageOffset
            OrderType.LIMIT -> if (order.direction == OrderSide.BUY) {
                minOf(order.requestedPrice, tick.ask)
            } else {
                maxOf(order.requestedPrice, tick.bid)
            }
            OrderType.STOP -> if (order.direction == OrderSide.BUY) tick.ask + slippageOffset else tick.bid - slippageOffset
            else -> order.requestedPrice
        }

        if (!executedPrice.isFinite() || executedPrice <= 0.0 ||
            !config.slippagePips.isFinite() || config.slippagePips < 0.0 ||
            !config.defaultCommissionPerLot.isFinite() || config.defaultCommissionPerLot < 0.0) {
            return ExecutionResult.Error("سعر التنفيذ أو إعدادات التداول غير صالحة")
        }

        val commission = config.defaultCommissionPerLot * order.volume
        if (!commission.isFinite() || commission < 0.0 ||
            !account.freeMargin.isFinite() || account.freeMargin < 0.0 ||
            !account.leverage.isFinite() || account.leverage <= 0.0) {
            return ExecutionResult.Error("العمولة أو رصيد الهامش أو الرافعة المالية غير صالح")
        }
        val margin = (order.volume * symInfo.contractSize * executedPrice) / account.leverage

        if (!margin.isFinite() || margin <= 0.0 || margin + commission > account.freeMargin) {
            return ExecutionResult.Error("الهامش الافتراضي غير كافٍ لتنفيذ الأمر المعلق")
        }

        val position = Position(
            accountId = account.id,
            symbol = symInfo.symbol,
            side = if (order.direction == OrderSide.BUY) PositionSide.BUY else PositionSide.SELL,
            volume = order.volume,
            entryPrice = executedPrice,
            currentPrice = executedPrice,
            stopLoss = order.stopLoss,
            takeProfit = order.takeProfit,
            openTime = tick.timestamp,
            profitLoss = 0.0,
            swap = 0.0,
            commission = commission,
            margin = margin,
            mode = mode
        )

        return ExecutionResult.Success(position, executedPrice, commission)
    }

    /**
     * Calculates valid Break-Even price with protection offset.
     * Prevents invalid break-even placement if position is currently not in profit.
     */
    fun calculateBreakEven(
        position: Position,
        tick: Tick,
        protectionOffsetPips: Double = 1.0
    ): Result<Double> {
        if (!position.symbol.equals(tick.symbol, ignoreCase = true) ||
            !tick.bid.isFinite() || !tick.ask.isFinite() ||
            tick.bid <= 0.0 || tick.ask < tick.bid ||
            !position.entryPrice.isFinite() || position.entryPrice <= 0.0 ||
            !protectionOffsetPips.isFinite() || protectionOffsetPips < 0.0) {
            return Result.failure(Exception("بيانات السعر أو حماية نقطة التعادل غير صالحة"))
        }
        val symInfo = DefaultSymbols.getSymbol(position.symbol)
        val offset = protectionOffsetPips * symInfo.pipSize
        if (!offset.isFinite()) {
            return Result.failure(Exception("قيمة حماية نقطة التعادل غير صالحة"))
        }

        return when (position.side) {
            PositionSide.BUY -> {
                if (tick.bid <= position.entryPrice) {
                    Result.failure(Exception("لا يمكن تفعيل نقطة التعادل: سعر البيع الحالي (${tick.bid}) أقل من أو يساوي سعر الدخول (${position.entryPrice})"))
                } else {
                    val stop = position.entryPrice + offset
                    if (!stop.isFinite() || stop >= tick.bid) {
                        Result.failure(Exception("مستوى التعادل للشراء يجب أن يبقى دون سعر البيع الحالي"))
                    } else {
                        Result.success(stop)
                    }
                }
            }
            PositionSide.SELL -> {
                if (tick.ask >= position.entryPrice) {
                    Result.failure(Exception("لا يمكن تفعيل نقطة التعادل: سعر الشراء الحالي (${tick.ask}) أعلى من أو يساوي سعر الدخول (${position.entryPrice})"))
                } else {
                    val stop = position.entryPrice - offset
                    if (!stop.isFinite() || stop <= tick.ask || stop <= 0.0) {
                        Result.failure(Exception("مستوى التعادل للبيع يجب أن يبقى فوق سعر الشراء الحالي"))
                    } else {
                        Result.success(stop)
                    }
                }
            }
        }
    }

    /**
     * Evaluates Trailing Stop. Returns new stop loss price ONLY if candidate moves by at least minStepPips.
     * Avoids excessive database writes on insignificant ticks.
     */
    fun calculateTrailingStopUpdate(
        position: Position,
        tick: Tick,
        minStepPips: Double = 1.0
    ): Double? {
        val distance = position.trailingStopDistance ?: return null
        if (!distance.isFinite() || distance <= 0.0 ||
            !minStepPips.isFinite() || minStepPips <= 0.0 ||
            !tick.bid.isFinite() || !tick.ask.isFinite() ||
            tick.bid <= 0.0 || tick.ask < tick.bid ||
            !position.symbol.equals(tick.symbol, ignoreCase = true)) return null
        val symInfo = DefaultSymbols.getSymbol(position.symbol)
        val minStep = minStepPips * symInfo.pipSize
        if (!minStep.isFinite() || minStep <= 0.0) return null

        return when (position.side) {
            PositionSide.BUY -> {
                val candidateSl = tick.bid - distance
                val currentSl = position.stopLoss
                if (candidateSl.isFinite() && candidateSl > 0.0 &&
                    (currentSl == null || candidateSl >= currentSl + minStep)) {
                    candidateSl
                } else {
                    null
                }
            }
            PositionSide.SELL -> {
                val candidateSl = tick.ask + distance
                val currentSl = position.stopLoss
                if (candidateSl.isFinite() && candidateSl > 0.0 &&
                    (currentSl == null || candidateSl <= currentSl - minStep)) {
                    candidateSl
                } else {
                    null
                }
            }
        }
    }

    /**
     * Evaluates an open position against the latest market tick.
     * Updates profit/loss, updates trailing stop, checks if SL or TP hit.
     */
    fun evaluatePositionOnTick(
        position: Position,
        tick: Tick
    ): PositionEvaluation {
        val symInfo = DefaultSymbols.getSymbol(position.symbol)

        // Close evaluation prices
        // BUY closes at Bid
        // SELL closes at Ask
        val currentPrice = when (position.side) {
            PositionSide.BUY -> tick.bid
            PositionSide.SELL -> tick.ask
        }

        // Calculate Gross P/L
        val grossPl = when (position.side) {
            PositionSide.BUY -> (tick.bid - position.entryPrice) * position.volume * symInfo.contractSize
            PositionSide.SELL -> (position.entryPrice - tick.ask) * position.volume * symInfo.contractSize
        }

        // Trailing stop adjustment using step threshold
        val trailingSl = calculateTrailingStopUpdate(position, tick)
        val updatedStopLoss = trailingSl ?: position.stopLoss

        // Check SL trigger
        if (updatedStopLoss != null) {
            val isSlTriggered = when (position.side) {
                PositionSide.BUY -> tick.bid <= updatedStopLoss
                PositionSide.SELL -> tick.ask >= updatedStopLoss
            }
            if (isSlTriggered) {
                return PositionEvaluation.TriggerClose(
                    // A stop is not a guaranteed fill price: gaps can execute worse.
                    exitPrice = when (position.side) {
                        PositionSide.BUY -> minOf(tick.bid, updatedStopLoss)
                        PositionSide.SELL -> maxOf(tick.ask, updatedStopLoss)
                    },
                    exitReason = if (position.isBreakEven) ExitReason.BREAK_EVEN else ExitReason.STOP_LOSS
                )
            }
        }

        // Check TP trigger
        if (position.takeProfit != null) {
            val isTpTriggered = when (position.side) {
                PositionSide.BUY -> tick.bid >= position.takeProfit
                PositionSide.SELL -> tick.ask <= position.takeProfit
            }
            if (isTpTriggered) {
                return PositionEvaluation.TriggerClose(
                    exitPrice = position.takeProfit,
                    exitReason = ExitReason.TAKE_PROFIT
                )
            }
        }

        val updatedPosition = position.copy(
            currentPrice = currentPrice,
            profitLoss = grossPl,
            stopLoss = updatedStopLoss
        )

        return PositionEvaluation.KeepOpen(updatedPosition)
    }

    /**
     * Evaluates an open position against a candle (useful for fast backtesting & replay).
     */
    fun evaluatePositionOnCandle(
        position: Position,
        candle: Candle
    ): PositionEvaluation {
        val symInfo = DefaultSymbols.getSymbol(position.symbol)

        // Check SL against candle extremes
        if (position.stopLoss != null) {
            val isSlTriggered = when (position.side) {
                PositionSide.BUY -> candle.low <= position.stopLoss
                PositionSide.SELL -> candle.high >= position.stopLoss
            }
            if (isSlTriggered) {
                return PositionEvaluation.TriggerClose(
                    // A candle opening beyond the stop indicates a gap; do not
                    // credit an impossible fill at the original stop level.
                    exitPrice = when (position.side) {
                        PositionSide.BUY -> minOf(candle.open, position.stopLoss)
                        PositionSide.SELL -> maxOf(candle.open, position.stopLoss)
                    },
                    exitReason = if (position.isBreakEven) ExitReason.BREAK_EVEN else ExitReason.STOP_LOSS
                )
            }
        }

        // Check TP against candle extremes
        if (position.takeProfit != null) {
            val isTpTriggered = when (position.side) {
                PositionSide.BUY -> candle.high >= position.takeProfit
                PositionSide.SELL -> candle.low <= position.takeProfit
            }
            if (isTpTriggered) {
                return PositionEvaluation.TriggerClose(
                    exitPrice = position.takeProfit,
                    exitReason = ExitReason.TAKE_PROFIT
                )
            }
        }

        // Position remains open at candle close
        val grossPl = when (position.side) {
            PositionSide.BUY -> (candle.close - position.entryPrice) * position.volume * symInfo.contractSize
            PositionSide.SELL -> (position.entryPrice - candle.close) * position.volume * symInfo.contractSize
        }

        val updatedPosition = position.copy(
            currentPrice = candle.close,
            profitLoss = grossPl
        )

        return PositionEvaluation.KeepOpen(updatedPosition)
    }

    /**
     * Closes an open position and creates a TradeJournalEntry.
     * Supports partial close while correctly updating remaining position and margin without duplication.
     */
    fun closePosition(
        position: Position,
        exitPrice: Double,
        exitReason: ExitReason,
        closeTime: Long = System.currentTimeMillis(),
        partialVolume: Double? = null
    ): Pair<TradeJournalEntry, Position?> {
        val symInfo = DefaultSymbols.getSymbol(position.symbol)
        require(position.volume.isFinite() && position.volume > 0.0) { "Invalid position volume" }
        require(exitPrice.isFinite() && exitPrice > 0.0) { "Invalid exit price" }
        require(partialVolume == null || (partialVolume.isFinite() &&
            partialVolume > 0.0 && partialVolume <= position.volume)) { "Invalid partial close volume" }
        val closingVolume = partialVolume ?: position.volume

        val grossPl = when (position.side) {
            PositionSide.BUY -> (exitPrice - position.entryPrice) * closingVolume * symInfo.contractSize
            PositionSide.SELL -> (position.entryPrice - exitPrice) * closingVolume * symInfo.contractSize
        }

        val ratio = closingVolume / position.volume
        val closingCommission = position.commission * ratio
        val closingSwap = position.swap * ratio

        // Calculate R-Multiple if SL was defined
        val rMultiple = if (position.stopLoss != null) {
            val riskPerUnit = abs(position.entryPrice - position.stopLoss)
            if (riskPerUnit > 0) {
                val priceGain = when (position.side) {
                    PositionSide.BUY -> exitPrice - position.entryPrice
                    PositionSide.SELL -> position.entryPrice - exitPrice
                }
                priceGain / riskPerUnit
            } else 0.0
        } else 0.0

        val journalEntry = TradeJournalEntry(
            accountId = position.accountId,
            symbol = position.symbol,
            side = position.side,
            volume = closingVolume,
            entryPrice = position.entryPrice,
            exitPrice = exitPrice,
            stopLoss = position.stopLoss,
            takeProfit = position.takeProfit,
            profitLoss = grossPl,
            commission = closingCommission,
            swap = closingSwap,
            openTime = position.openTime,
            closeTime = closeTime,
            strategyId = position.strategyId,
            exitReason = exitReason,
            rMultiple = rMultiple,
            mode = position.mode
        )

        val remainingVolume = position.volume - closingVolume
        val remainingPosition = if (remainingVolume > 1e-9) {
            // Preserve the actual original margin basis instead of assuming 1:100 leverage.
            val remMargin = position.margin * (remainingVolume / position.volume)
            position.copy(
                volume = remainingVolume,
                commission = (position.commission - closingCommission).coerceAtLeast(0.0),
                swap = (position.swap - closingSwap).coerceAtLeast(0.0),
                margin = remMargin
            )
        } else {
            null
        }

        return Pair(journalEntry, remainingPosition)
    }
}

sealed class PositionEvaluation {
    data class KeepOpen(val updatedPosition: Position) : PositionEvaluation()
    data class TriggerClose(val exitPrice: Double, val exitReason: ExitReason) : PositionEvaluation()
}
