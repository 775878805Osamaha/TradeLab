package com.example.feature.chart

import com.example.core.indicators.*
import com.example.core.model.Candle
import com.example.feature.chart.model.IndicatorSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

data class PreparedChartIndicators(
    val sma: List<Double?> = emptyList(),
    val ema: List<Double?> = emptyList(),
    val bollinger: List<BollingerBandsResult?> = emptyList(),
    val vwap: List<Double> = emptyList(),
    val rsi: List<Double?> = emptyList(),
    val macd: List<MacdResult?> = emptyList(),
    val atr: List<Double?> = emptyList()
)

/** Cancel obsolete CPU work between and within indicator stages; publish one complete result. */
object ChartIndicatorPreparation {
    suspend fun calculate(candles: List<Candle>, settings: IndicatorSettings): PreparedChartIndicators =
        withContext(Dispatchers.Default) {
            val context=currentCoroutineContext()
            val checkpoint: () -> Unit = { context.ensureActive() }
            checkpoint()
            val result=PreparedChartIndicators(
                sma=if(settings.isSmaEnabled) TechnicalIndicators.calculateSma(candles,settings.smaPeriod,checkpoint) else emptyList(),
                ema=if(settings.isEmaEnabled) TechnicalIndicators.calculateEma(candles,settings.emaPeriod,checkpoint) else emptyList(),
                bollinger=if(settings.isBollingerEnabled) TechnicalIndicators.calculateBollingerBands(candles,settings.bollingerPeriod,settings.bollingerStdDev,checkpoint) else emptyList(),
                vwap=if(settings.isVwapEnabled) TechnicalIndicators.calculateVwap(candles,checkpoint) else emptyList(),
                rsi=if(settings.isRsiEnabled) TechnicalIndicators.calculateRsi(candles,settings.rsiPeriod,checkpoint) else emptyList(),
                macd=if(settings.isMacdEnabled) TechnicalIndicators.calculateMacd(candles,settings.macdFast,settings.macdSlow,settings.macdSignal,checkpoint) else emptyList(),
                atr=if(settings.isAtrEnabled) TechnicalIndicators.calculateAtr(candles,settings.atrPeriod,checkpoint) else emptyList()
            )
            checkpoint()
            result
        }
}
