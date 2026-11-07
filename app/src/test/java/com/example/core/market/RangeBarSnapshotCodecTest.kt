package com.example.core.market

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

class RangeBarSnapshotCodecTest {
    private val source = "ctrader:demo:7:12"
    private val symbol = "XAUUSD"
    private val bars = VerifiedRangeBars(
        listOf(Candle(symbol, Timeframe.M1, 100L, 201L, 4071.0, 4081.0,
            4070.0, 4080.0, 0.0, source)),
        RangeTickDiagnostics(30000, 80, 4, 1010L, 200L, 1), true)

    @Test fun genuineCompletedBarsAndAllDiagnosticsSurviveLosslessDiskRoundTrip() {
        val saved = RangeBarSnapshotCodec.encode(symbol, source, bars)
        assertEquals(bars, RangeBarSnapshotCodec.decode(symbol, source, saved))
        assertEquals(VerifiedRangeBars(emptyList(), RangeTickDiagnostics(), false),
            RangeBarSnapshotCodec.decode(symbol, source,
                RangeBarSnapshotCodec.encode(symbol, source,
                    VerifiedRangeBars(emptyList(), RangeTickDiagnostics(), false))))
    }

    @Test fun invalidOhlcAndUnverifiedBrokerSourcesCanNeverBePersisted() {
        assertThrows(IllegalArgumentException::class.java) {
            RangeBarSnapshotCodec.encode(symbol, "synthetic", bars)
        }
        assertThrows(IllegalArgumentException::class.java) {
            RangeBarSnapshotCodec.encode(symbol, source, bars.copy(candles = listOf(
                bars.candles.single().copy(high = 4050.0))))
        }
    }

    @Test fun chartWarmRestoreNeverUsesFutureReplayBarsOrDistantHistory() {
        assertTrue(RangeBarWarmRestorePolicy.canPreview(
            3_600_000L, 7_200_000L, 3_660_000L, 7_260_000L))
        assertFalse(RangeBarWarmRestorePolicy.canPreview(
            3_600_000L, 7_300_000L, 3_660_000L, 7_260_000L))
        assertFalse(RangeBarWarmRestorePolicy.canPreview(
            1_000L, 2_000L, 4_000_000L, 7_260_000L))
    }
}
