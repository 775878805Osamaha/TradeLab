package com.example.feature.replay

import com.example.core.model.Candle
import com.example.core.model.Timeframe
import org.junit.Assert.*
import org.junit.Test

/** Regression suite for the exact older-candles error seen on the Replay chart. */
class ReplayChartLookbackIntegrityTest {
    private val step=Timeframe.M15.minutes*60_000L
    private val first=step*2_000_000L
    private fun bar(offset:Long,source:String="CTRADER_HISTORICAL",symbol:String="XAUUSD",
        timeframe:Timeframe=Timeframe.M15,close:Double=4000.25):Candle =
        Candle(symbol,timeframe,first+offset*step,
            open=4000.0,high=4000.5,low=3999.5,close=close,volume=3.0,source=source)

    @Test fun overlappingBrokerPageIsDeduplicatedWithoutError() {
        val old=listOf(bar(-3),bar(-2),bar(-1))
        val page=listOf(bar(-6),bar(-5),bar(-4),bar(-3),bar(-2))
        val merged=ReplayChartLookback.prepend(old,page,first,"XAUUSD",Timeframe.M15)
        assertEquals(6,merged.size)
        assertEquals(((-6L)..(-1L)).map { first+it*step },merged.map { it.openTime })
    }

    @Test fun outOfOrderNetworkResponseIsSortedWithoutInventingBars() {
        val page=listOf(bar(-2),bar(-5),bar(-1),bar(-3))
        val merged=ReplayChartLookback.prepend(emptyList(),page,first,"XAUUSD",Timeframe.M15)
        assertEquals(4,merged.size)
        assertEquals(listOf(-5L,-3L,-2L,-1L).map { first+it*step },merged.map{it.openTime})
    }

    @Test fun exactDuplicatesInsideSingleResponseAreHarmless() {
        val page=listOf(bar(-2),bar(-1),bar(-2))
        val merged=ReplayChartLookback.prepend(emptyList(),page,first,"XAUUSD",Timeframe.M15)
        assertEquals(2,merged.size)
    }

    @Test fun conflictingDuplicatesCannotRewritePastPrices() {
        val old=listOf(bar(-3),bar(-2))
        val conflicting=listOf(bar(-4),bar(-3,close=4000.35))
        val error=assertThrows(ReplayChartLookback.InvalidPage::class.java) {
            ReplayChartLookback.prepend(old,conflicting,first,"XAUUSD",Timeframe.M15)
        }
        assertEquals(ReplayChartLookback.Reason.DUPLICATE_CONFLICT,error.reason)
        assertEquals(listOf(-3L,-2L).map { first+it*step },old.map {it.openTime})
    }

    @Test fun wrongSymbolIsReportedPrecisely() {
        val e=assertThrows(ReplayChartLookback.InvalidPage::class.java) {
            ReplayChartLookback.prepend(emptyList(),listOf(bar(-1,symbol="EURUSD")),
                first,"XAUUSD",Timeframe.M15)
        }
        assertEquals(ReplayChartLookback.Reason.SYMBOL,e.reason)
    }

    @Test fun wrongTimeframeIsReportedPrecisely() {
        val e=assertThrows(ReplayChartLookback.InvalidPage::class.java) {
            ReplayChartLookback.prepend(emptyList(),listOf(bar(-1,timeframe=Timeframe.H1)),
                first,"XAUUSD",Timeframe.M15)
        }
        assertEquals(ReplayChartLookback.Reason.TIMEFRAME,e.reason)
    }

    @Test fun oldProvidersNeverPassAsCTrader() {
        for(source in listOf("BIQUOTE_REST","TWELVE_DATA","HISTDATA","DUKASCOPY",
            "BINANCE_HISTORICAL")) {
            val e=assertThrows(ReplayChartLookback.InvalidPage::class.java) {
                ReplayChartLookback.prepend(emptyList(),listOf(bar(-1,source=source)),
                    first,"XAUUSD",Timeframe.M15)
            }
            assertEquals(source,ReplayChartLookback.Reason.SOURCE,e.reason)
        }
    }

    @Test fun noFutureOrEngineBarCanEnterChartPrehistory() {
        for(offset in listOf(0L,1L,100L)) {
            val e=assertThrows(ReplayChartLookback.InvalidPage::class.java) {
                ReplayChartLookback.prepend(emptyList(),listOf(bar(offset)),
                    first,"XAUUSD",Timeframe.M15)
            }
            assertEquals(ReplayChartLookback.Reason.FUTURE_REPLAY,e.reason)
        }
    }

    @Test fun weekendAndHolidayGapsAreKeptWithoutSyntheticPrices() {
        val page=listOf(bar(-200),bar(-199),bar(-1))
        val merged=ReplayChartLookback.prepend(emptyList(),page,first,"XAUUSD",Timeframe.M15)
        assertEquals(3,merged.size)
        assertEquals(bar(-199).openTime,merged[1].openTime)
        assertEquals(bar(-1).openTime,merged[2].openTime)
    }

    @Test fun identicalBinanceCacheOverlapDoesNotBecomeAnotherProvider() {
        val older=listOf(bar(-3,source="BINANCE_HISTORICAL_CACHED",symbol="BTCUSDT"))
        val newer=listOf(
            bar(-4,source="BINANCE_HISTORICAL",symbol="BTCUSDT"),
            bar(-3,source="BINANCE_HISTORICAL",symbol="BTCUSDT")
        )
        val merged=ReplayChartLookback.prepend(older,newer,first,"BTCUSDT",Timeframe.M15)
        assertEquals(2,merged.size)
    }

    @Test fun staleDatasetWithWrongTimeframeNeverReceivesMorePages() {
        val old=listOf(bar(-1,timeframe=Timeframe.M5))
        val e=assertThrows(ReplayChartLookback.InvalidPage::class.java) {
            ReplayChartLookback.prepend(old,listOf(bar(-2)),first,"XAUUSD",Timeframe.M15)
        }
        assertEquals(ReplayChartLookback.Reason.TIMEFRAME,e.reason)
    }
}
