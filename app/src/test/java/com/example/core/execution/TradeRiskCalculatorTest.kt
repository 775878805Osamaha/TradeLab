package com.example.core.execution

import com.example.core.model.OrderSide
import org.junit.Assert.*
import org.junit.Test

class TradeRiskCalculatorTest {
    @Test fun goldBuyRiskUsesHundredOuncesPerLot() {
        val result = TradeRiskCalculator.estimate("XAUUSD", OrderSide.BUY,
            4000.0, 3990.0, 4020.0, 0.1, 10_000.0, 1.0)!!
        assertEquals(100.0, result.riskUsd, 0.001)
        assertEquals(200.0, result.rewardUsd!!, 0.001)
        assertEquals(2.0, result.rewardRiskRatio!!, 0.001)
        assertEquals(1.0, result.riskPercentOfEquity!!, 0.001)
        assertEquals(0.1, result.maximumLotsForRisk!!, 0.001)
    }

    @Test fun forexSellRiskAndRewardAreDirectional() {
        val result = TradeRiskCalculator.estimate("EURUSD", OrderSide.SELL,
            1.1000, 1.1020, 1.0960, 0.1)!!
        assertEquals(20.0, result.riskUsd, 0.001)
        assertEquals(40.0, result.rewardUsd!!, 0.001)
    }

    @Test fun jpyQuoteIsConvertedToUsd() {
        val result = TradeRiskCalculator.estimate("USDJPY", OrderSide.BUY,
            150.0, 149.0, null, 0.1)!!
        assertEquals(100000.0 / 150.0 * 0.1, result.riskUsd, 0.001)
    }

    @Test fun buyStopAboveEntryIsRejected() {
        assertNull(TradeRiskCalculator.estimate("XAUUSD", OrderSide.BUY,
            4000.0, 4010.0, null, 0.1))
    }

    @Test fun sellStopBelowEntryIsRejected() {
        assertNull(TradeRiskCalculator.estimate("EURUSD", OrderSide.SELL,
            1.1, 1.09, null, 0.1))
    }

    @Test fun targetWrongSideIsRejected() {
        assertNull(TradeRiskCalculator.estimate("XAUUSD", OrderSide.BUY,
            4000.0, 3990.0, 3980.0, 0.1))
    }

    @Test fun unsupportedSymbolIsRejected() {
        assertNull(TradeRiskCalculator.estimate("UNKNOWN", OrderSide.BUY,
            4000.0, 3990.0, null, 0.1))
    }

    @Test fun nonFiniteInputsAreRejected() {
        assertNull(TradeRiskCalculator.estimate("XAUUSD", OrderSide.BUY,
            Double.NaN, 3990.0, null, 0.1))
        assertNull(TradeRiskCalculator.estimate("XAUUSD", OrderSide.BUY,
            4000.0, 3990.0, null, Double.POSITIVE_INFINITY))
    }

    @Test fun riskLotSizingRoundsDownToStep() {
        val result = TradeRiskCalculator.estimate("XAUUSD", OrderSide.BUY,
            4000.0, 3990.0, null, 0.1, 10500.0, 1.0)!!
        assertEquals(0.1, result.maximumLotsForRisk!!, 0.001)
    }

    @Test fun tooSmallRiskBudgetReturnsNoEligibleLots() {
        val result = TradeRiskCalculator.estimate("XAUUSD", OrderSide.BUY,
            4000.0, 3990.0, null, 0.1, 100.0, 1.0)!!
        assertNull(result.maximumLotsForRisk)
    }
}
