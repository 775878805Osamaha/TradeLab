package com.example.ui.components.chart

import org.junit.Assert.assertEquals
import org.junit.Test

class QuotePriceFormatterTest {
    @Test fun keepsSmallForexQuotesReadable() {
        assertEquals("1.0843", QuotePriceFormatter.price(1.0843))
        assertEquals("0.00012345", QuotePriceFormatter.price(0.00012345))
    }

    @Test fun formatsLargePricesAndInvalidValuesSafely() {
        assertEquals("67500.25", QuotePriceFormatter.price(67500.25))
        assertEquals("—", QuotePriceFormatter.price(Double.NaN))
        assertEquals("—", QuotePriceFormatter.spread(Double.POSITIVE_INFINITY))
        assertEquals("—", QuotePriceFormatter.spread(-1.0))
    }

    @Test fun tinyPositiveQuotesAreNotRoundedToZero() {
        assertEquals("0.000000000123", QuotePriceFormatter.price(0.000000000123))
        assertEquals("0.000000000123", QuotePriceFormatter.spread(0.000000000123))
        assertEquals("0.00", QuotePriceFormatter.price(0.0))
        assertEquals("—", QuotePriceFormatter.price(-1.0))
    }

    @Test fun subPicounitPricesUseScientificNotationRatherThanZero() {
        assertEquals("5.0000e-14", QuotePriceFormatter.price(5e-14))
        assertEquals("5.0000e-14", QuotePriceFormatter.spread(5e-14))
        assertEquals("0.000000000001", QuotePriceFormatter.price(1e-12))
    }

    @Test fun retainsSmallRawSpreads() {
        assertEquals("0.00012000", QuotePriceFormatter.spread(0.00012))
        assertEquals("0.250000", QuotePriceFormatter.spread(0.25))
    }
}
