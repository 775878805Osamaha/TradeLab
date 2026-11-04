package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.time.Instant

class ReplayDateHistoryTest {
    private fun time(value: String) = Instant.parse(value).toEpochMilli()
    private val now = time("2026-10-28T12:00:00Z")
    private val target = time("2025-10-28T12:00:00Z")
    private val minute = 60_000L
    private fun candle(at: Long) = Candle("XAUUSD", Timeframe.M1, at,
        open=100.0, high=101.0, low=99.0, close=100.0, volume=1.0)

    @Test fun yearJumpFetchesOnlyOneBoundedMinuteWindow() = runBlocking {
        val windows = ReplayDateWindow.windows(target, now, minute, 300)
        var requests = 0
        val loaded = ReplayDateHistory.load(windows, target) { from, to ->
            requests++
            assertEquals(300L, (to - from) / minute + 1)
            listOf(candle(target - minute), candle(target), candle(target + minute))
        }!!
        assertEquals(1, requests)
        assertEquals(target, loaded.candles.first { it.openTime >= target }.openTime)
        assertTrue(loaded.window.to < now - 300L * 86_400_000L)
    }

    @Test fun yearIsCalendarYearIncludingLeapDay() {
        assertEquals(time("2023-02-28T12:30:00Z"),
            ReplayDateWindow.oneYearBefore(time("2024-02-29T12:30:00Z")))
        assertEquals(target, ReplayDateWindow.oneYearBefore(now))
    }

    @Test fun windowsRemainContiguousAlignedAndClosedForAllSupportedIntervals() {
        for (interval in listOf(1,3,5,15,30,60,120,240,1440,10080).map { it*minute }) {
            val windows = ReplayDateWindow.windows(target, now, interval, 300)
            assertTrue(windows.size in 1..64)
            assertTrue(windows.all { it.from >= 0 && it.to - it.from <= 299*interval &&
                it.to < HistoricalCandleBoundary.currentOpen(now, interval) })
            assertTrue(windows.zipWithNext().all { (a,b) -> a.to+interval==b.from })
            assertEquals(HistoricalCandleBoundary.currentOpen(windows.first().from, interval), windows.first().from)
        }
    }

    @Test fun confirmedClosedSessionsScanForwardWithoutInventingBars() = runBlocking {
        val windows = ReplayDateWindow.windows(target, now, minute, 300)
        var requests = 0
        val loaded = ReplayDateHistory.load(windows, target) { from, _ ->
            requests++
            if (requests < 3) throw NoHistoricalCandlesException("XAUUSD")
            listOf(candle(from), candle(from + minute))
        }!!
        assertEquals(3, requests)
        assertEquals(windows[2], loaded.window)
        assertEquals(2, loaded.candles.size)
    }

    @Test fun networkFailuresAndCancellationDoNotTriggerSessionScanning() = runBlocking {
        for (failure in listOf(IOException("offline"), CancellationException("cancelled"))) {
            var requests = 0
            try {
                ReplayDateHistory.load(ReplayDateWindow.windows(target, now, minute, 300), target) { _, _ ->
                    requests++
                    throw failure
                }
                fail("Request failure must propagate")
            } catch (actual: Exception) { assertSame(failure, actual) }
            assertEquals(1, requests)
        }
    }

    @Test fun providerReturningRecentPricesForOldDateIsRejected() = runBlocking {
        try {
            ReplayDateHistory.load(ReplayDateWindow.windows(target, now, minute, 300), target) { _, _ ->
                listOf(candle(now-minute), candle(now-2*minute))
            }
            fail("Wrong date must fail")
        } catch (_: IllegalArgumentException) { }
    }

    @Test fun warmupOnlyPageDoesNotPretendToReachTarget() = runBlocking {
        val windows = ReplayDateWindow.windows(target, now, minute, 300)
        var requests = 0
        val loaded = ReplayDateHistory.load(windows, target) { from, _ ->
            requests++
            if (requests == 1) listOf(candle(target-2*minute), candle(target-minute))
            else listOf(candle(from), candle(from+minute))
        }!!
        assertEquals(2, requests)
        assertTrue(loaded.candles.first().openTime > target)
    }

    @Test fun futureDateFailsBeforeFetchingAndSearchHasFiniteBudget() {
        try {
            ReplayDateWindow.windows(now, now, minute, 300)
            fail("Forming candle is not history")
        } catch (_: IllegalArgumentException) { }
        assertEquals(64, ReplayDateWindow.windows(target, now, minute, 50).size)
    }

    @Test fun recentForexWeekendFallsBackToEarlierRealBrokerCandles() = runBlocking {
        val sunday = time("2026-11-01T12:00:00Z")
        val windows = ReplayDateWindow.recentWindows(sunday, minute, 300, 0, 72)
        assertTrue(windows.size > 2)
        assertTrue(windows.zipWithNext().all { (newer, older) ->
            newer.from == older.to + minute
        })
        var attempts = 0
        val loaded = ReplayDateHistory.load(windows, null) { from, _ ->
            attempts++
            if (attempts <= 2) throw NoHistoricalCandlesException("XAUUSD")
            listOf(candle(from), candle(from + minute))
        }!!
        assertEquals(3, attempts)
        assertEquals(windows[2], loaded.window)
        assertEquals(2, loaded.candles.size)
    }

    @Test fun weekendScanNeverSynthesizesPricesOrMasksNetworkErrors() = runBlocking {
        val sunday = time("2026-11-01T12:00:00Z")
        val windows = ReplayDateWindow.recentWindows(sunday, minute, 300, 0, 72)
        assertNull(ReplayDateHistory.load(windows, null) { _, _ ->
            throw NoHistoricalCandlesException("XAUUSD")
        })
        var attempts = 0
        val transportError = IOException("offline")
        try {
            ReplayDateHistory.load(windows, null) { _, _ ->
                attempts++
                throw transportError
            }
            fail("Transport errors must not trigger a lengthy closed-session scan")
        } catch (actual: IOException) { assertSame(transportError, actual) }
        assertEquals(1, attempts)
        assertEquals(1, ReplayDateWindow.recentWindows(sunday, minute, 300, 0).size)
    }

    @Test fun cTraderRecentWindowsIncludeBrokerOpensAfterThePreviousUtcDailyBoundary() {
        val today = time("2026-11-04T23:30:00Z")
        val day = 86_400_000L
        val previousBrokerOpen = time("2026-11-03T22:00:00Z")
        val broker = ReplayDateWindow.recentWindows(today, day, 50, 0,
            brokerTimed = true)
        val exchange = ReplayDateWindow.recentWindows(today, day, 50, 0)
        assertTrue(previousBrokerOpen in broker.first().from..broker.first().to)
        assertFalse(previousBrokerOpen in exchange.first().from..exchange.first().to)
        assertEquals(time("2026-11-03T23:30:00Z"), broker.first().to)
    }

    @Test fun cTraderDatePickerKeepsTheActualBrokerSessionMinute() {
        val now = time("2026-11-04T23:30:00Z")
        val targetAtBrokerOpen = time("2025-10-26T22:01:00Z")
        val interval = 4L * 3_600_000L
        val windows = ReplayDateWindow.windows(targetAtBrokerOpen, now, interval, 50,
            brokerTimed = true)
        assertTrue(windows.first().from % 60_000L == 0L)
        assertEquals(Math.floorMod(targetAtBrokerOpen, interval),
            Math.floorMod(windows.first().from, interval))
        assertTrue(windows.zipWithNext().all { (a, b) -> a.to + interval == b.from })
    }
}
