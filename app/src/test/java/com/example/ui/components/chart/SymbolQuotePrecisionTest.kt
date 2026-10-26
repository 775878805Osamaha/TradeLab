package com.example.ui.components.chart

import org.junit.Assert.*
import org.junit.Test

class SymbolQuotePrecisionTest {
    @Test fun euroPreservesFifthDecimal() {
        assertEquals("1.12345", QuotePriceFormatter.forSymbol(1.12345, "EURUSD"))
    }
    @Test fun yenPreservesThirdDecimal() {
        assertEquals("147.362", QuotePriceFormatter.forSymbol(147.362, "USDJPY"))
    }
    @Test fun goldUsesTwoDecimalsAndGrouping() {
        assertEquals("4,016.30", QuotePriceFormatter.forSymbol(4016.3, "XAUUSD", grouping = true))
    }
    @Test fun zoomedAxisCanDisplaySubTickGridIntervals() {
        assertEquals("1.123456", QuotePriceFormatter.forSymbol(1.123456, "EURUSD", minimumDecimals = 6))
    }
    @Test fun unknownTinyQuoteNeverBecomesZero() {
        val formatted = QuotePriceFormatter.forSymbol(0.00000000000001, "UNKNOWN")
        assertTrue(formatted.contains("e"))
        assertFalse(formatted.startsWith("0.0000"))
    }
    @Test fun invalidSourceValuesAreNotDisplayedAsRealQuotes() {
        assertEquals("—", QuotePriceFormatter.forSymbol(Double.NaN, "EURUSD"))
        assertEquals("—", QuotePriceFormatter.forSymbol(Double.POSITIVE_INFINITY, "USDJPY"))
        assertEquals("—", QuotePriceFormatter.forSymbol(-1.0, "XAUUSD"))
    }
}
