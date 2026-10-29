package com.example.feature.chart

import com.example.core.indicators.*
import com.example.core.model.Candle
import com.example.core.model.Timeframe
import com.example.feature.chart.model.IndicatorSettings
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class ChartIndicatorPreparationTest {
    private fun candle(i: Int, close: Double=100.0, volume: Double=2.0)=Candle("XAUUSD",Timeframe.M1,i*60_000L,
        open=close,high=close+1,low=close-1,close=close,volume=volume,source="TEST_FIXTURE")
    private val all=IndicatorSettings(isSmaEnabled=true,smaPeriod=3,isEmaEnabled=true,emaPeriod=3,
        isBollingerEnabled=true,bollingerPeriod=3,isVwapEnabled=true,isRsiEnabled=true,rsiPeriod=2,
        isMacdEnabled=true,macdFast=2,macdSlow=3,macdSignal=2,isAtrEnabled=true,atrPeriod=3)

    @Test fun constantSeriesKeepsLegacyWarmupsAndValues() = runBlocking {
        val result=ChartIndicatorPreparation.calculate(List(10) { candle(it) },all)
        assertEquals(listOf(null,null),result.sma.take(2));assertTrue(result.sma.drop(2).all { it==100.0 })
        assertEquals(result.sma,result.ema)
        assertEquals(listOf(null,null),result.rsi.take(2));assertTrue(result.rsi.drop(2).all { it==100.0 })
        assertTrue(result.bollinger.take(2).all { it==null })
        assertTrue(result.bollinger.drop(2).all { it==BollingerBandsResult(100.0,100.0,100.0) })
        assertEquals(listOf(null,null),result.atr.take(2));assertTrue(result.atr.drop(2).all { it==2.0 })
        assertTrue(result.macd.take(3).all { it==null })
        assertTrue(result.macd.drop(3).all { it==MacdResult(0.0,0.0,0.0) })
        assertTrue(result.vwap.all { it==100.0 })
    }

    @Test fun changingPriceFixtureKeepsNumericalResults() = runBlocking {
        val bars=listOf(100.0,102.0,101.0,105.0,103.0,106.0).mapIndexed { i,close -> candle(i,close,i+1.0) }
        val result=ChartIndicatorPreparation.calculate(bars,all)
        assertEquals(104.66666666666667,result.sma.last()!!,1e-10)
        assertEquals(104.5,result.ema.last()!!,1e-10)
        assertEquals(79.06976744186046,result.rsi.last()!!,1e-10)
        assertEquals(278.0/81,result.atr.last()!!,1e-10)
        assertEquals(103.71428571428571,result.vwap.last(),1e-10)
        assertEquals(107.16110492451597,result.bollinger.last()!!.upper,1e-10)
        assertEquals(102.17222840881737,result.bollinger.last()!!.lower,1e-10)
        assertEquals(.5740740740740762,result.macd.last()!!.macd,1e-10)
        assertEquals(.4691358024691374,result.macd.last()!!.signal,1e-10)
    }

    @Test fun disabledIndicatorsNeverReadLargeHistory() = runBlocking {
        val bars=object : AbstractList<Candle>() {
            override val size=100_001
            override fun get(index: Int): Candle=error("Disabled indicators must not scan history")
        }
        assertEquals(PreparedChartIndicators(),ChartIndicatorPreparation.calculate(bars,IndicatorSettings(isEmaEnabled=false)))
    }

    @Test fun enabledLargeSeriesArePreparedOffTheCallingThread() = runBlocking {
        val caller=Thread.currentThread()
        val bars=object : AbstractList<Candle>() {
            override val size=100_001
            override fun get(index: Int): Candle {
                check(Thread.currentThread() !== caller) { "Indicator scanned history on UI caller" }
                return candle(index)
            }
        }
        val result=ChartIndicatorPreparation.calculate(bars,all)
        assertEquals(List(7) { 100_001 },listOf(result.sma.size,result.ema.size,result.bollinger.size,
            result.vwap.size,result.rsi.size,result.macd.size,result.atr.size))
    }

    @Test fun allSevenIndicatorsStopObsoleteCalculationsCooperatively() = runBlocking {
        val calculators: List<Pair<String,(List<Candle>,()->Unit)->Unit>> = listOf(
            "SMA" to { bars,cp -> TechnicalIndicators.calculateSma(bars,20,cp);Unit },
            "EMA" to { bars,cp -> TechnicalIndicators.calculateEma(bars,20,cp);Unit },
            "RSI" to { bars,cp -> TechnicalIndicators.calculateRsi(bars,14,cp);Unit },
            "MACD" to { bars,cp -> TechnicalIndicators.calculateMacd(bars,12,26,9,cp);Unit },
            "ATR" to { bars,cp -> TechnicalIndicators.calculateAtr(bars,14,cp);Unit },
            "Bollinger" to { bars,cp -> TechnicalIndicators.calculateBollingerBands(bars,20,2.0,cp);Unit },
            "VWAP" to { bars,cp -> TechnicalIndicators.calculateVwap(bars,cp);Unit }
        )
        for((name,calculate) in calculators) {
            val job=Job();var reads=0
            val bars=object : AbstractList<Candle>() {
                override val size=100_001
                override fun get(index: Int): Candle {
                    if(++reads==3_000) job.cancel()
                    return candle(index)
                }
            }
            try {
                withContext(job+Dispatchers.Default) {
                    val context=currentCoroutineContext()
                    calculate(bars) { context.ensureActive() }
                }
                fail("$name completed obsolete work")
            } catch (_: CancellationException) { assertTrue("$name reads=$reads",reads in 3_000..10_000) }
            finally { job.cancel() }
        }
    }

    @Test fun cancellationAlsoStopsInsideAWideBollingerWindow() = runBlocking {
        val job=Job();var reads=0
        val bars=object : AbstractList<Candle>() {
            override val size=5_000
            override fun get(index: Int): Candle {
                if(++reads==7_000) job.cancel() // After the 6,000 reads of the SMA stage.
                return candle(index)
            }
        }
        try {
            withContext(job+Dispatchers.Default) {
                val context=currentCoroutineContext()
                TechnicalIndicators.calculateBollingerBands(bars,4_000,2.0) { context.ensureActive() }
            }
            fail("Bollinger variance loop ignored cancellation")
        } catch (_: CancellationException) { assertTrue("reads=$reads",reads in 7_000..8_024) }
        finally { job.cancel() }
    }
}
