package com.example

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.example.core.model.*
import com.example.feature.chart.PositionActionsDialog
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class PositionActionsDialogTest {
    @get:Rule val compose = createComposeRule()
    private val position = Position(id = 7, accountId = 1, symbol = "GBPUSD", side = PositionSide.BUY,
        volume = 0.1, entryPrice = 1.3, currentPrice = 1.31, takeProfit = 1.4)
    private val tick = Tick("GBPUSD", 1.31, 1.3102)

    @Test fun partialCloseRequiresSmallerPositiveVolumeAndPassesExactAmount() {
        var closed: Double? = null
        compose.setContent { MaterialTheme { PositionActionsDialog(position, tick, {}, { closed = it }, { _, _ -> }) } }
        compose.onNodeWithTag("position_partial").performClick()
        compose.onNodeWithTag("position_action_value").performTextInput("0.1")
        compose.onNodeWithTag("position_action_confirm").assertIsNotEnabled()
        compose.onNodeWithTag("position_action_value").performTextReplacement("0.04")
        compose.onNodeWithTag("position_action_confirm").performClick()
        assertEquals(0.04, closed!!, 0.000001)
    }

    @Test fun buyStopRejectsWrongSideAndPreservesExistingTarget() {
        var stop: Double? = null
        var target: Double? = null
        compose.setContent { MaterialTheme { PositionActionsDialog(position, tick, {}, {}, { sl, tp -> stop = sl; target = tp }) } }
        compose.onNodeWithTag("position_sl").performClick()
        compose.onNodeWithTag("position_action_value").performTextInput("1.32")
        compose.onNodeWithTag("position_action_confirm").assertIsNotEnabled()
        compose.onNodeWithTag("position_action_value").performTextReplacement("1.29")
        compose.onNodeWithTag("position_action_confirm").performClick()
        assertEquals(1.29, stop!!, 0.000001)
        assertEquals(1.4, target!!, 0.000001)
    }

    @Test fun fullCloseRequiresExplicitConfirmation() {
        var closed = false
        compose.setContent { MaterialTheme { PositionActionsDialog(position, tick, {}, { closed = true }, { _, _ -> }) } }
        compose.onNodeWithTag("position_close").performClick()
        assertFalse(closed)
        compose.onNodeWithTag("position_action_confirm").performClick()
        assertTrue(closed)
    }
}
