package com.example.core.market

import org.junit.Assert.*
import org.junit.Test

class RangeCandleVisualPolicyTest {
    @Test fun genuineRangeCandlesNeverInheritHollowStyleFromOldPreferences() {
        for (up in listOf(true, false)) for (hollow in listOf(true, false)) {
            assertFalse(RangeCandleVisualPolicy.outline(true, false, up, hollow, false))
        }
    }

    @Test fun visualOnlyGapRemainsDistinguishableAndOtherStylesPreserved() {
        assertTrue(RangeCandleVisualPolicy.outline(true, true, true, false, false))
        assertTrue(RangeCandleVisualPolicy.outline(false, false, true, true, false))
        assertTrue(RangeCandleVisualPolicy.outline(false, false, true, false, true))
        assertFalse(RangeCandleVisualPolicy.outline(false, false, false, true, true))
    }
}
