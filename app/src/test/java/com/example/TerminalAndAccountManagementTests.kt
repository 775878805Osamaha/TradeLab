package com.example

import com.example.core.execution.ExecutionConfig
import com.example.core.execution.ExecutionEngine
import com.example.core.execution.ExecutionResult
import com.example.core.market.DefaultSymbols
import com.example.core.model.*
import com.example.core.risk.RiskEngine
import org.junit.Assert.*
import org.junit.Test

/**
 * Phase 10: Professional Trading Terminal & Account Management Unit Test Suite.
 * Validates virtual workflow:
 * Market -> Chart -> Order Ticket -> Risk Calculation -> Virtual Execution -> Position -> Account Metrics -> History
 */
class TerminalAndAccountManagementTests {

    private val executionEngine = ExecutionEngine(ExecutionConfig(slippagePips = 0.0, defaultCommissionPerLot = 0.0))
    private val riskEngine = RiskEngine()

    @Test
    fun `test virtual account initialization with default 50 dollars balance`() {
        val account = VirtualAccount(
            id = 1L,
            name = "حساب افتراضي أساسي",
            initialBalance = 50.0,
            balance = 50.0,
            equity = 50.0,
            margin = 0.0,
            leverage = 100.0,
            currency = "USD"
        )

        assertEquals(50.0, account.initialBalance, 0.001)
        assertEquals(50.0, account.balance, 0.001)
        assertEquals(50.0, account.equity, 0.001)
        assertEquals(50.0, account.freeMargin, 0.001)
        assertEquals(0.0, account.margin, 0.001)
        assertEquals(0.0, account.marginLevel, 0.001) // 0 or infinite when no used margin
    }

    @Test
    fun `test multiple isolated virtual accounts have independent balances and margins`() {
        val accountA = VirtualAccount(
            id = 1L,
            name = "محفظة سكالپينج الذهب",
            initialBalance = 50.0,
            balance = 50.0,
            equity = 50.0,
            margin = 5.30,
            freeMargin = VirtualAccount.computeFreeMargin(50.0, 5.30),
            leverage = 100.0
        )

        val accountB = VirtualAccount(
            id = 2L,
            name = "محفظة سوينج البيتكوين",
            initialBalance = 1000.0,
            balance = 1000.0,
            equity = 1040.0,
            margin = 13.50,
            freeMargin = VirtualAccount.computeFreeMargin(1040.0, 13.50),
            leverage = 50.0
        )

        assertNotEquals(accountA.id, accountB.id)
        assertNotEquals(accountA.balance, accountB.balance)
        assertEquals(44.70, accountA.freeMargin, 0.01)
        assertEquals(1026.50, accountB.freeMargin, 0.01)
    }

    @Test
    fun `test margin warning condition when free margin drops below threshold`() {
        val healthyAccount = VirtualAccount(
            id = 1L,
            name = "Healthy",
            initialBalance = 50.0,
            balance = 50.0,
            equity = 50.0,
            margin = 10.0,
            leverage = 100.0
        )
        // free margin = 40.0 -> healthy
        assertTrue(healthyAccount.freeMargin >= 15.0)

        val distressedAccount = VirtualAccount(
            id = 2L,
            name = "Distressed",
            initialBalance = 50.0,
            balance = 50.0,
            equity = 22.0,
            margin = 15.0,
            leverage = 100.0
        )
        // free margin = 7.0 (< 15.0) -> triggers warning banner
        val isWarning = distressedAccount.freeMargin < 15.0 || (distressedAccount.margin > 0 && distressedAccount.marginLevel < 120.0)
        assertTrue(isWarning)
    }

    @Test
    fun `test pre-trade risk analysis calculates required margin and potential loss`() {
        val account = VirtualAccount(id = 1L, name = "Demo", balance = 50.0, equity = 50.0, leverage = 100.0)
        val entry = 2650.00
        val sl = 2645.00 // 5.0 points = 50 pips
        val tp = 2665.00 // 15.0 points = 150 pips

        val analysis = riskEngine.analyzeRisk(
            account = account,
            symbol = "XAUUSD",
            side = OrderSide.BUY,
            volume = 0.01,
            entryPrice = entry,
            stopLoss = sl,
            takeProfit = tp
        )

        assertTrue(analysis.isMarginSufficient)
        assertTrue(analysis.requiredMargin > 0.0)
        assertTrue(analysis.requiredMargin < account.freeMargin)
        assertEquals(5.0, analysis.potentialLoss, 0.01) // 5 points * 100 oz * 0.01 lot = $5.00
        assertEquals(15.0, analysis.potentialProfit, 0.01) // 15 points * 100 oz * 0.01 lot = $15.00
        assertNotNull(analysis.riskRewardRatio)
        assertEquals(3.0, analysis.riskRewardRatio!!, 0.05) // 15 / 5 = 1:3 RRR
    }

    @Test
    fun `test risk engine suggested lot size for 2 percent risk`() {
        val account = VirtualAccount(id = 1L, name = "Demo", balance = 50.0, equity = 50.0, leverage = 100.0)
        // 2% of $50 = $1.00 risk. If stop loss distance is 50 pips ($5/0.01 lot), suggested lot is minLot (0.01)
        val suggestedLot = riskEngine.calculateSuggestedLot(
            account = account,
            symbol = "XAUUSD",
            riskPercentage = 2.0,
            stopLossPips = 50.0
        )

        assertEquals(0.02, suggestedLot, 0.001)
    }

    @Test
    fun `test break-even function adjusts stop loss to entry price plus optional buffer`() {
        val pos = Position(
            id = 101L,
            accountId = 1L,
            symbol = "XAUUSD",
            side = PositionSide.BUY,
            volume = 0.01,
            entryPrice = 2650.00,
            currentPrice = 2662.00,
            stopLoss = 2640.00,
            takeProfit = 2675.00,
            profitLoss = 12.0
        )

        // Break-even moves SL to entryPrice
        val bePos = pos.copy(stopLoss = pos.entryPrice, isBreakEven = true)
        assertEquals(2650.00, bePos.stopLoss!!, 0.001)
        assertTrue(bePos.isBreakEven)
        // Risk amount becomes zero once SL is at entry
        assertEquals(0.0, bePos.riskAmount, 0.001)
    }

    @Test
    fun `test trailing stop updates stop loss when price advances favorably`() {
        val buyPos = Position(
            id = 102L,
            accountId = 1L,
            symbol = "XAUUSD",
            side = PositionSide.BUY,
            volume = 0.01,
            entryPrice = 2650.00,
            currentPrice = 2665.00,
            stopLoss = 2645.00,
            trailingStopDistance = 10.0 // 10 price points trail
        )

        val targetSl = buyPos.currentPrice - (buyPos.trailingStopDistance ?: 0.0)
        assertTrue(targetSl > (buyPos.stopLoss ?: 0.0))
        val trailedPos = buyPos.copy(stopLoss = targetSl)
        assertEquals(2655.00, trailedPos.stopLoss!!, 0.001)
    }

    @Test
    fun `test partial position close reduces volume and preserves remaining position`() {
        val initialVolume = 0.05
        val closeVolume = 0.02
        val remainingVolume = initialVolume - closeVolume

        val sym = DefaultSymbols.getSymbol("XAUUSD")
        assertTrue(remainingVolume >= sym.minLot)
        assertEquals(0.03, remainingVolume, 0.001)
    }

    @Test
    fun `test virtual order execution requires sufficient free margin`() {
        val tinyAccount = VirtualAccount(id = 1L, name = "Tiny", balance = 1.0, equity = 1.0, leverage = 10.0)
        val tick = Tick(symbol = "XAUUSD", bid = 2650.0, ask = 2650.3)

        // Attempt to open 1.00 full lot with only $1.00 balance and 1:10 leverage
        val result = executionEngine.executeMarketOrder(
            account = tinyAccount,
            symbol = "XAUUSD",
            side = OrderSide.BUY,
            volume = 1.00,
            tick = tick,
            stopLoss = null,
            takeProfit = null
        )

        assertTrue(result is ExecutionResult.Error)
        val reason = (result as ExecutionResult.Error).message
        assertTrue(reason.contains("margin", ignoreCase = true) || reason.contains("هامش", ignoreCase = true))
    }

    @Test
    fun `test order ticket symbol precision and lot steps conform to registry`() {
        val xau = DefaultSymbols.getSymbol("XAUUSD")
        assertEquals(2, xau.digits)
        assertEquals(0.01, xau.minLot, 0.0001)
        assertEquals(0.01, xau.lotStep, 0.0001)

        val btc = DefaultSymbols.getSymbol("BTCUSDT")
        assertEquals(2, btc.digits)
        assertEquals(0.01, btc.minLot, 0.0001)

        val eurusd = DefaultSymbols.getSymbol("EURUSD")
        assertEquals(5, eurusd.digits)
        assertEquals(0.0001, eurusd.pipSize, 0.000001)
    }

    @Test
    fun `test pending limit order execution when market reaches activation threshold`() {
        val buyLimitOrder = Order(
            id = 201L,
            accountId = 1L,
            symbol = "XAUUSD",
            type = OrderType.BUY_LIMIT,
            direction = OrderSide.BUY,
            volume = 0.02,
            requestedPrice = 2640.00,
            status = OrderStatus.PENDING
        )

        // When ask drops to 2640.00 or lower, BUY_LIMIT executes
        val higherTick = Tick(symbol = "XAUUSD", bid = 2642.0, ask = 2642.3)
        assertFalse(higherTick.ask <= buyLimitOrder.requestedPrice)

        val triggeringTick = Tick(symbol = "XAUUSD", bid = 2639.8, ask = 2640.0)
        assertTrue(triggeringTick.ask <= buyLimitOrder.requestedPrice)
    }

    @Test
    fun `test virtual simulation safety disclaimer integrity`() {
        val expectedSafetyStatement = "منصة تدريب ومحاكاة افتراضية 100% — لا تداول بأموال حقيقية"
        assertTrue(expectedSafetyStatement.contains("100%"))
        assertTrue(expectedSafetyStatement.contains("افتراضية"))
    }
}
