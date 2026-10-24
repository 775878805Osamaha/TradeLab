package com.example.feature.backtest

import org.junit.Assert.*
import org.junit.Test

class BacktestConfigInputTest {
    @Test fun parsesOrdinaryAndScientificNumbers() {
        assertEquals(50.0, parseBacktestNumber("الرصيد", " 50 "), 0.0)
        assertEquals(1000.0, parseBacktestNumber("الرصيد", "1e3"), 0.0)
    }

    @Test fun rejectsBlankAndNonNumericInput() {
        for (input in listOf("", "  ", "abc", "12x")) {
            try {
                parseBacktestNumber("رأس المال", input)
                fail("Accepted invalid value: $input")
            } catch (e: IllegalArgumentException) {
                assertTrue(e.message!!.contains("رأس المال"))
            }
        }
    }

    @Test fun rejectsNanAndInfinity() {
        for (input in listOf("NaN", "Infinity", "-Infinity", "1e999")) {
            try {
                parseBacktestNumber("المخاطرة", input)
                fail("Accepted non-finite value: $input")
            } catch (_: IllegalArgumentException) {}
        }
    }

    @Test fun zeroAndNegativeAreParsedForDomainValidation() {
        assertEquals(0.0, parseBacktestNumber("السبريد", "0"), 0.0)
        assertEquals(-2.0, parseBacktestNumber("السبريد", "-2"), 0.0)
    }
}
