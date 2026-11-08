package com.example.core.market

import org.junit.Assert.*
import org.junit.Test

class RangeSymbolPrecisionTest {
    @Test fun brokerDisplayDigitsValidateRatherThanSilentlyReplaceTickSize() {
        val gold = RangeSymbolPrecision(3, 2)
        assertTrue(gold.isConfiguredTickRepresentable(0.01))
        assertTrue(gold.isConfiguredTickRepresentable(0.001))
        assertFalse(gold.isConfiguredTickRepresentable(0.0001))
        assertFalse(gold.isConfiguredTickRepresentable(0.0155))
        assertFalse(gold.isConfiguredTickRepresentable(Double.NaN))
        assertFalse(gold.isConfiguredTickRepresentable(0.0))
    }

    @Test fun typicalForexPrecisionIsAccountSpecific() {
        val forex = RangeSymbolPrecision(5, 4)
        assertTrue(forex.isConfiguredTickRepresentable(0.00001))
        assertTrue(forex.isConfiguredTickRepresentable(0.0001))
        assertFalse(forex.isConfiguredTickRepresentable(0.000001))
        assertFalse(forex.isConfiguredTickRepresentable(0.000015))
    }

    @Test fun brokerMetadataMustBeWithinProtocolBounds() {
        assertThrows(IllegalArgumentException::class.java) { RangeSymbolPrecision(-1, 2) }
        assertThrows(IllegalArgumentException::class.java) { RangeSymbolPrecision(11, 2) }
    }
}
