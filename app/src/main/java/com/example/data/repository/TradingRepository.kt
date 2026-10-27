package com.example.data.repository

import com.example.core.execution.ExecutionConfig
import com.example.core.execution.ExecutionEngine
import com.example.core.execution.OrderValidationResult
import com.example.core.execution.OrderValidator
import com.example.core.execution.PositionEvaluation
import com.example.core.market.DefaultSymbols
import com.example.core.model.*
import com.example.core.risk.RiskEngine
import com.example.data.local.dao.AccountDao
import com.example.data.local.dao.OrderDao
import com.example.data.local.dao.PositionDao
import com.example.data.local.dao.TradeDao
import com.example.data.local.entity.AccountEntity
import com.example.data.local.entity.OrderEntity
import com.example.data.local.entity.PositionEntity
import com.example.data.local.entity.TradeEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

import com.example.data.local.dao.BacktestDao
import com.example.data.local.entity.BacktestRunEntity

class TradingRepository(
    private val accountDao: AccountDao,
    private val positionDao: PositionDao,
    private val orderDao: OrderDao,
    private val tradeDao: TradeDao,
    private val backtestDao: BacktestDao? = null,
    val executionEngine: ExecutionEngine = ExecutionEngine(),
    val riskEngine: RiskEngine = RiskEngine(),
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) {

    val replayReport = MutableStateFlow<ReplayReport?>(null)

    // Cached live tick prices for high-frequency position evaluation without DB churn
    private val latestTicks = ConcurrentHashMap<String, Tick>()

    val allAccounts: Flow<List<VirtualAccount>> = accountDao.getAllAccounts().map { entities ->
        entities.map { it.toDomain() }
    }

    val selectedAccount: Flow<VirtualAccount?> = accountDao.getSelectedAccountFlow().map { it?.toDomain() }

    fun getPositionsForAccount(accountId: Long): Flow<List<Position>> {
        return positionDao.getPositionsForAccount(accountId).map { entities ->
            entities.map { entity ->
                val pos = entity.toDomain()
                val tick = latestTicks[pos.symbol]
                if (tick != null) {
                    val currentPrice = if (pos.side == PositionSide.BUY) tick.bid else tick.ask
                    val symInfo = DefaultSymbols.getSymbol(pos.symbol)
                    val grossPl = if (pos.side == PositionSide.BUY) {
                        (tick.bid - pos.entryPrice) * pos.volume * symInfo.contractSize
                    } else {
                        (pos.entryPrice - tick.ask) * pos.volume * symInfo.contractSize
                    }
                    pos.copy(currentPrice = currentPrice, profitLoss = grossPl)
                } else {
                    pos
                }
            }
        }
    }

    fun getPendingOrdersForAccount(accountId: Long): Flow<List<Order>> {
        return orderDao.getOrdersForAccount(accountId).map { entities ->
            entities.filter { it.status == OrderStatus.PENDING.name }.map { it.toDomain() }
        }
    }

    fun getTradesForAccount(accountId: Long): Flow<List<TradeJournalEntry>> {
        return tradeDao.getTradesForAccount(accountId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    suspend fun initializeDefaultAccountIfNeeded() = withContext(Dispatchers.IO) {
        val existing = accountDao.getSelectedAccount()
        if (existing == null) {
            val defaultAcc = AccountEntity(
                name = "حساب تداول الذهب (XAUUSD)",
                initialBalance = 50.0,
                balance = 50.0,
                equity = 50.0,
                margin = 0.0,
                freeMargin = 50.0,
                marginLevel = 0.0,
                leverage = 100.0,
                currency = "USD",
                mode = AccountMode.LIVE_PAPER.name,
                isSelected = true,
                createdAt = System.currentTimeMillis()
            )
            accountDao.insertAccount(defaultAcc)
        }
    }

    suspend fun createAccount(name: String, initialBalance: Double = 50.0, leverage: Double = 100.0): Long = withContext(Dispatchers.IO) {
        accountDao.clearSelection()
        val entity = AccountEntity(
            name = name,
            initialBalance = initialBalance,
            balance = initialBalance,
            equity = initialBalance,
            margin = 0.0,
            freeMargin = initialBalance,
            marginLevel = 0.0,
            leverage = leverage,
            currency = "USD",
            mode = AccountMode.LIVE_PAPER.name,
            isSelected = true,
            createdAt = System.currentTimeMillis()
        )
        accountDao.insertAccount(entity)
    }

    suspend fun selectAccount(id: Long) = withContext(Dispatchers.IO) {
        accountDao.clearSelection()
        accountDao.selectAccount(id)
    }

    suspend fun resetAccount(accountId: Long, balance: Double = 50.0) = withContext(Dispatchers.IO) {
        val acc = accountDao.getAccountById(accountId) ?: return@withContext
        positionDao.deletePositionsForAccount(accountId)
        orderDao.deleteOrdersForAccount(accountId)
        tradeDao.deleteTradesForAccount(accountId)

        accountDao.updateAccount(
            acc.copy(
                balance = balance,
                equity = balance,
                margin = 0.0,
                freeMargin = balance,
                marginLevel = 0.0,
                initialBalance = balance
            )
        )
    }

    suspend fun deleteAccount(accountId: Long) = withContext(Dispatchers.IO) {
        positionDao.deletePositionsForAccount(accountId)
        orderDao.deleteOrdersForAccount(accountId)
        tradeDao.deleteTradesForAccount(accountId)
        accountDao.deleteAccountById(accountId)
    }

    /**
     * Executes a market order atomically.
     * Enforces strict order validation, updates balance, margin, and audit record.
     */
    suspend fun executeMarketOrder(
        accountId: Long,
        symbol: String,
        side: OrderSide,
        volume: Double,
        tick: Tick,
        stopLoss: Double?,
        takeProfit: Double?,
        mode: String = "LIVE_PAPER"
    ): Result<Position> = withContext(Dispatchers.IO) {
        val accountEntity = accountDao.getAccountById(accountId)
            ?: return@withContext Result.failure(Exception("الحساب غير موجود"))

        val account = accountEntity.toDomain()

        val execResult = executionEngine.executeMarketOrder(
            account = account,
            symbol = symbol,
            side = side,
            volume = volume,
            tick = tick,
            stopLoss = stopLoss,
            takeProfit = takeProfit,
            mode = mode
        )

        when (execResult) {
            is com.example.core.execution.ExecutionResult.Success -> {
                val pos = execResult.position
                val posId = positionDao.insertPosition(pos.toEntity())
                val createdPosition = pos.copy(id = posId)

                // Insert filled order audit record
                val orderEntity = OrderEntity(
                    accountId = account.id,
                    symbol = pos.symbol,
                    type = OrderType.MARKET.name,
                    side = side.name,
                    volume = volume,
                    requestedPrice = execResult.executedPrice,
                    stopLoss = stopLoss,
                    takeProfit = takeProfit,
                    status = OrderStatus.FILLED.name,
                    createdAt = tick.timestamp,
                    executedPrice = execResult.executedPrice,
                    executedAt = tick.timestamp,
                    comment = "VIRTUAL_MARKET_FILL"
                )
                orderDao.insertOrder(orderEntity)

                // Deduct commission from balance & adjust margin
                val updatedBalance = account.balance - execResult.commission
                recalculateAccountTotals(account.id, updatedBalance)

                Result.success(createdPosition)
            }
            is com.example.core.execution.ExecutionResult.Error -> {
                Result.failure(Exception(execResult.message))
            }
            else -> Result.failure(Exception("فشل تنفيذ الأمر"))
        }
    }

    /**
     * Places a pending order (BUY LIMIT, SELL LIMIT, BUY STOP, SELL STOP).
     */
    suspend fun placePendingOrder(
        accountId: Long,
        symbol: String,
        type: OrderType,
        side: OrderSide,
        volume: Double,
        requestedPrice: Double,
        stopLoss: Double?,
        takeProfit: Double?,
        tick: Tick?
    ): Result<Order> = withContext(Dispatchers.IO) {
        val accountEntity = accountDao.getAccountById(accountId)
            ?: return@withContext Result.failure(Exception("الحساب غير موجود"))

        val account = accountEntity.toDomain()

        val validation = OrderValidator.validate(
            account = account,
            symbol = symbol,
            type = type,
            side = side,
            volume = volume,
            tick = tick,
            requestedPrice = requestedPrice,
            stopLoss = stopLoss,
            takeProfit = takeProfit
        )

        if (validation is OrderValidationResult.Rejected) {
            return@withContext Result.failure(Exception(validation.message))
        }

        val orderEntity = OrderEntity(
            accountId = accountId,
            symbol = symbol,
            type = type.name,
            side = side.name,
            volume = volume,
            requestedPrice = requestedPrice,
            stopLoss = stopLoss,
            takeProfit = takeProfit,
            status = OrderStatus.PENDING.name,
            createdAt = System.currentTimeMillis(),
            executedPrice = null,
            executedAt = null,
            comment = "PENDING_ORDER"
        )

        val id = orderDao.insertOrder(orderEntity)
        Result.success(orderEntity.copy(id = id).toDomain())
    }

    suspend fun cancelPendingOrder(orderId: Long): Result<Unit> = withContext(Dispatchers.IO) {
        orderDao.deleteOrder(orderId)
        Result.success(Unit)
    }

    /**
     * Closes an open position fully or partially.
     */
    suspend fun closePosition(
        positionId: Long,
        exitPrice: Double,
        exitReason: ExitReason,
        partialVolume: Double? = null
    ): Result<TradeJournalEntry> = withContext(Dispatchers.IO) {
        val posEntity = positionDao.getPositionById(positionId)
            ?: return@withContext Result.failure(Exception("الصفقة غير موجودة"))

        val pos = posEntity.toDomain()
        val (journalEntry, remainingPos) = executionEngine.closePosition(
            position = pos,
            exitPrice = exitPrice,
            exitReason = exitReason,
            closeTime = System.currentTimeMillis(),
            partialVolume = partialVolume
        )

        // Save trade entry to journal
        tradeDao.insertTrade(journalEntry.toEntity())

        if (remainingPos != null) {
            positionDao.updatePosition(remainingPos.toEntity())
        } else {
            positionDao.deletePosition(pos.id)
        }

        // Update account balance
        val accEntity = accountDao.getAccountById(pos.accountId)
        if (accEntity != null) {
            val newBalance = accEntity.balance + journalEntry.netProfitLoss
            recalculateAccountTotals(pos.accountId, newBalance)
        }

        Result.success(journalEntry)
    }

    suspend fun modifyPosition(
        positionId: Long,
        stopLoss: Double?,
        takeProfit: Double?
    ): Result<Unit> = withContext(Dispatchers.IO) {
        val posEntity = positionDao.getPositionById(positionId)
            ?: return@withContext Result.failure(Exception("الصفقة غير موجودة"))

        // Never persist nonfinite or nonpositive risk levels. A profitable
        // trailing/break-even stop may cross entry, so validate against the
        // current executable quote when available rather than entry alone.
        if ((stopLoss != null && (!stopLoss.isFinite() || stopLoss <= 0.0)) ||
            (takeProfit != null && (!takeProfit.isFinite() || takeProfit <= 0.0))) {
            return@withContext Result.failure(Exception("مستوى وقف الخسارة أو جني الأرباح غير صالح"))
        }
        val tick = latestTicks[posEntity.symbol]
        if (tick != null) {
            val isBuy = posEntity.side == PositionSide.BUY.name
            val executablePrice = if (isBuy) tick.bid else tick.ask
            if (stopLoss != null && (if (isBuy) stopLoss >= executablePrice else stopLoss <= executablePrice)) {
                return@withContext Result.failure(Exception("وقف الخسارة يجب أن يكون في الجانب الصحيح من سعر السوق"))
            }
            if (takeProfit != null && (if (isBuy) takeProfit <= executablePrice else takeProfit >= executablePrice)) {
                return@withContext Result.failure(Exception("جني الأرباح يجب أن يكون في الجانب الصحيح من سعر السوق"))
            }
        }

        positionDao.updatePosition(
            posEntity.copy(stopLoss = stopLoss, takeProfit = takeProfit)
        )
        Result.success(Unit)
    }

    suspend fun setBreakEven(positionId: Long, protectionOffsetPips: Double = 1.0): Result<Double> = withContext(Dispatchers.IO) {
        val posEntity = positionDao.getPositionById(positionId)
            ?: return@withContext Result.failure(Exception("الصفقة غير موجودة"))

        val pos = posEntity.toDomain()
        val tick = latestTicks[pos.symbol]
            ?: return@withContext Result.failure(Exception("بيانات السعر المباشر غير متوفرة"))

        val beResult = executionEngine.calculateBreakEven(pos, tick, protectionOffsetPips)
        if (beResult.isFailure) {
            return@withContext Result.failure(beResult.exceptionOrNull() ?: Exception("فشل تفعيل نقطة التعادل"))
        }

        val bePrice = beResult.getOrThrow()
        positionDao.updatePosition(
            posEntity.copy(stopLoss = bePrice, isBreakEven = true)
        )
        Result.success(bePrice)
    }

    suspend fun setTrailingStop(positionId: Long, distancePips: Double): Result<Unit> = withContext(Dispatchers.IO) {
        val posEntity = positionDao.getPositionById(positionId)
            ?: return@withContext Result.failure(Exception("الصفقة غير موجودة"))

        if (!distancePips.isFinite() || distancePips <= 0.0) {
            return@withContext Result.failure(Exception("مسافة الوقف المتحرك يجب أن تكون موجبة وصالحة"))
        }
        val symInfo = DefaultSymbols.getSymbol(posEntity.symbol)
        val distancePrice = distancePips * symInfo.pipSize
        if (!distancePrice.isFinite() || distancePrice <= 0.0) {
            return@withContext Result.failure(Exception("مسافة الوقف المتحرك المحسوبة غير صالحة"))
        }

        positionDao.updatePosition(
            posEntity.copy(trailingStopDistance = distancePrice)
        )
        Result.success(Unit)
    }

    /**
     * Evaluates incoming ticks against pending orders and open positions.
     * Throttles database updates so only real triggers (SL/TP, pending fills, trailing stops) write to disk.
     */
    suspend fun onTickUpdate(tick: Tick) = withContext(Dispatchers.IO) {
        // Reject corrupted provider ticks before caching quotes or touching any account.
        if (!com.example.core.market.DataIntegrityValidator.validateTick(tick).isValid) {
            return@withContext
        }
        // Ignore delayed out-of-order ticks to avoid reverting market state and
        // accidentally triggering orders on prices older than the last accepted quote.
        val previous = latestTicks[tick.symbol]
        if (previous != null && tick.timestamp < previous.timestamp) {
            return@withContext
        }
        latestTicks[tick.symbol] = tick
        val currentAccount = accountDao.getSelectedAccount() ?: return@withContext

        // 1. Check pending orders for this symbol
        val pendingOrders = orderDao.getPendingOrders(currentAccount.id).filter { it.symbol == tick.symbol }
        for (po in pendingOrders) {
            val domainOrder = po.toDomain()
            val exec = executionEngine.evaluatePendingOrder(domainOrder, tick, currentAccount.toDomain())
            if (exec is com.example.core.execution.ExecutionResult.Success) {
                positionDao.insertPosition(exec.position.toEntity())
                orderDao.updateOrder(
                    po.copy(
                        status = OrderStatus.FILLED.name,
                        executedPrice = exec.executedPrice,
                        executedAt = tick.timestamp
                    )
                )
                recalculateAccountTotals(currentAccount.id)
            }
        }

        // 2. Evaluate open positions for SL/TP hits and trailing stop steps
        val positions = positionDao.getPositionsSync(currentAccount.id).filter { it.symbol == tick.symbol }
        var hasPositionClosed = false

        for (posEntity in positions) {
            val pos = posEntity.toDomain()
            when (val eval = executionEngine.evaluatePositionOnTick(pos, tick)) {
                is PositionEvaluation.TriggerClose -> {
                    closePosition(pos.id, eval.exitPrice, eval.exitReason)
                    hasPositionClosed = true
                }
                is PositionEvaluation.KeepOpen -> {
                    // Only write to Room if trailing stop has moved by at least 1 pip
                    if (eval.updatedPosition.stopLoss != pos.stopLoss) {
                        positionDao.updatePosition(eval.updatedPosition.toEntity())
                    }
                }
            }
        }

        if (hasPositionClosed) {
            recalculateAccountTotals(currentAccount.id)
        }
    }

    private suspend fun recalculateAccountTotals(accountId: Long, forcedBalance: Double? = null) {
        val acc = accountDao.getAccountById(accountId) ?: return
        val openPositions = positionDao.getPositionsSync(accountId).map { it.toDomain() }

        val balance = forcedBalance ?: acc.balance
        val totalPl = openPositions.sumOf { it.profitLoss }
        val totalMargin = openPositions.sumOf { it.margin }
        val totalCommission = openPositions.sumOf { it.commission }
        val totalSwap = openPositions.sumOf { it.swap }

        val equity = VirtualAccount.computeEquity(balance, totalPl, 0.0)
        val freeMargin = VirtualAccount.computeFreeMargin(equity, totalMargin)
        val marginLevel = VirtualAccount.computeMarginLevel(equity, totalMargin)

        accountDao.updateAccount(
            acc.copy(
                balance = balance,
                equity = equity,
                margin = totalMargin,
                freeMargin = freeMargin,
                marginLevel = marginLevel
            )
        )
    }

    // Mapping extensions
    private fun AccountEntity.toDomain(): VirtualAccount = VirtualAccount(
        id = id,
        name = name,
        initialBalance = initialBalance,
        balance = balance,
        equity = equity,
        margin = margin,
        freeMargin = freeMargin,
        marginLevel = marginLevel,
        leverage = leverage,
        currency = currency,
        mode = AccountMode.valueOf(mode),
        isSelected = isSelected,
        createdAt = createdAt
    )

    private fun PositionEntity.toDomain(): Position = Position(
        id = id,
        accountId = accountId,
        symbol = symbol,
        side = PositionSide.valueOf(side),
        volume = volume,
        entryPrice = entryPrice,
        currentPrice = currentPrice,
        stopLoss = stopLoss,
        takeProfit = takeProfit,
        openTime = openTime,
        profitLoss = profitLoss,
        swap = swap,
        commission = commission,
        margin = margin,
        strategyId = strategyId,
        mode = mode,
        trailingStopDistance = trailingStopDistance,
        isBreakEven = isBreakEven
    )

    private fun Position.toEntity(): PositionEntity = PositionEntity(
        id = id,
        accountId = accountId,
        symbol = symbol,
        side = side.name,
        volume = volume,
        entryPrice = entryPrice,
        currentPrice = currentPrice,
        stopLoss = stopLoss,
        takeProfit = takeProfit,
        openTime = openTime,
        profitLoss = profitLoss,
        swap = swap,
        commission = commission,
        margin = margin,
        strategyId = strategyId,
        mode = mode,
        trailingStopDistance = trailingStopDistance,
        isBreakEven = isBreakEven
    )

    private fun OrderEntity.toDomain(): Order = Order(
        id = id,
        accountId = accountId,
        symbol = symbol,
        direction = OrderSide.valueOf(side),
        type = OrderType.valueOf(type),
        volume = volume,
        requestedPrice = requestedPrice,
        executionPrice = executedPrice,
        stopLoss = stopLoss,
        takeProfit = takeProfit,
        status = OrderStatus.valueOf(status),
        createdAt = createdAt,
        filledAt = executedAt,
        cancelledAt = null,
        commission = 0.0,
        swap = 0.0,
        slippage = 0.0,
        comment = comment
    )

    private fun TradeEntity.toDomain(): TradeJournalEntry = TradeJournalEntry(
        id = id,
        accountId = accountId,
        symbol = symbol,
        side = PositionSide.valueOf(side),
        volume = volume,
        entryPrice = entryPrice,
        exitPrice = exitPrice,
        stopLoss = stopLoss,
        takeProfit = takeProfit,
        profitLoss = profitLoss,
        commission = commission,
        swap = swap,
        openTime = openTime,
        closeTime = closeTime,
        strategyId = strategyId,
        exitReason = ExitReason.valueOf(exitReason),
        rMultiple = rMultiple,
        notes = notes,
        mode = mode
    )

    private fun TradeJournalEntry.toEntity(): TradeEntity = TradeEntity(
        id = id,
        accountId = accountId,
        symbol = symbol,
        side = side.name,
        volume = volume,
        entryPrice = entryPrice,
        exitPrice = exitPrice,
        stopLoss = stopLoss,
        takeProfit = takeProfit,
        profitLoss = profitLoss,
        commission = commission,
        swap = swap,
        openTime = openTime,
        closeTime = closeTime,
        strategyId = strategyId,
        exitReason = exitReason.name,
        rMultiple = rMultiple,
        notes = notes,
        mode = mode
    )

    val allBacktestRuns: Flow<List<BacktestRun>> = backtestDao?.getAllRuns()?.map { entities ->
        entities.map { it.toDomain() }
    } ?: flowOf(emptyList())

    suspend fun saveBacktestRun(run: BacktestRun): Long = withContext(Dispatchers.IO) {
        backtestDao?.insertRun(run.toEntity()) ?: 0L
    }

    suspend fun deleteBacktestRun(id: Long) = withContext(Dispatchers.IO) {
        backtestDao?.deleteRun(id)
    }

    private fun BacktestRunEntity.toDomain(): BacktestRun = BacktestRun(
        id = id,
        strategyId = strategyId,
        strategyName = strategyName,
        symbol = symbol,
        timeframe = try { Timeframe.valueOf(timeframe) } catch (e: Exception) { Timeframe.M15 },
        startTime = startTime,
        endTime = endTime,
        initialBalance = initialBalance,
        finalBalance = finalBalance,
        netProfit = netProfit,
        returnPercentage = returnPercentage,
        totalTrades = totalTrades,
        winningTrades = winningTrades,
        losingTrades = losingTrades,
        maxDrawdown = maxDrawdown,
        maxDrawdownPercentage = maxDrawdownPct,
        profitFactor = profitFactor,
        winRate = winRatePct,
        expectancy = expectancy,
        status = try { BacktestRunStatus.valueOf(status) } catch (e: Exception) { BacktestRunStatus.COMPLETED },
        startedAt = startedAt,
        completedAt = completedAt,
        duration = duration,
        errorMessage = errorMessage
    )

    private fun BacktestRun.toEntity(): BacktestRunEntity = BacktestRunEntity(
        id = id,
        strategyId = strategyId,
        strategyName = strategyName,
        symbol = symbol,
        timeframe = timeframe.name,
        startTime = startTime,
        endTime = endTime,
        initialBalance = initialBalance,
        finalBalance = finalBalance,
        netProfit = netProfit,
        winRatePct = winRate,
        profitFactor = profitFactor,
        maxDrawdownPct = maxDrawdownPercentage,
        totalTrades = totalTrades,
        metricsJson = "",
        equityCurveJson = "",
        executedAt = completedAt,
        winningTrades = winningTrades,
        losingTrades = losingTrades,
        maxDrawdown = maxDrawdown,
        returnPercentage = returnPercentage,
        expectancy = expectancy,
        status = status.name,
        startedAt = startedAt,
        completedAt = completedAt,
        duration = duration,
        errorMessage = errorMessage
    )
}
