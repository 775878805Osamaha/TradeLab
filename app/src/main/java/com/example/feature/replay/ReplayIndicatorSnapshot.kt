package com.example.feature.replay

import com.example.core.indicators.BollingerBandsResult
import com.example.core.indicators.MacdResult
import com.example.core.indicators.TechnicalIndicators
import com.example.core.model.Candle
import com.example.feature.chart.model.IndicatorSettings

/**
 * One immutable result per revealed replay candle set. Calculation is dispatched
 * off the UI thread by ReplayScreen; only revealed candles are passed in.
 */
internal data class ReplayIndicatorSnapshot(
    val sma: List<Double?> = emptyList(),
    val ema: List<Double?> = emptyList(),
    val bollinger: List<BollingerBandsResult?> = emptyList(),
    val vwap: List<Double> = emptyList(),
    val rsi: List<Double?> = emptyList(),
    val macd: List<MacdResult?> = emptyList(),
    val atr: List<Double?> = emptyList()
) {
    companion object {
        fun calculate(candles: List<Candle>, settings: IndicatorSettings): ReplayIndicatorSnapshot =
            ReplayIndicatorSnapshot(
                sma = if (settings.isSmaEnabled) TechnicalIndicators.calculateSma(candles, settings.smaPeriod) else emptyList(),
                ema = if (settings.isEmaEnabled) TechnicalIndicators.calculateEma(candles, settings.emaPeriod) else emptyList(),
                bollinger = if (settings.isBollingerEnabled) TechnicalIndicators.calculateBollingerBands(candles, settings.bollingerPeriod, settings.bollingerStdDev) else emptyList(),
                vwap = if (settings.isVwapEnabled) TechnicalIndicators.calculateVwap(candles) else emptyList(),
                rsi = if (settings.isRsiEnabled) TechnicalIndicators.calculateRsi(candles, settings.rsiPeriod) else emptyList(),
                macd = if (settings.isMacdEnabled) TechnicalIndicators.calculateMacd(candles, settings.macdFast, settings.macdSlow, settings.macdSignal) else emptyList(),
                atr = if (settings.isAtrEnabled) TechnicalIndicators.calculateAtr(candles, settings.atrPeriod) else emptyList()
            )
    }
}
