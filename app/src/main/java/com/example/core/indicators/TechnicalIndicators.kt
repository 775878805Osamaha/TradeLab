package com.example.core.indicators

import com.example.core.model.Candle
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

data class MacdResult(val macd: Double, val signal: Double, val histogram: Double)
data class BollingerBandsResult(val middle: Double, val upper: Double, val lower: Double)

object TechnicalIndicators {

    /**
     * Simple Moving Average (SMA)
     */
    fun calculateSma(candles: List<Candle>, period: Int, checkpoint: () -> Unit = {}): List<Double?> {
        checkpoint()
        if (candles.size < period) return List(candles.size) { if(it%1024==0) checkpoint(); null }
        val result = mutableListOf<Double?>()
        var sum = 0.0

        for (i in candles.indices) {
            if(i%1024==0) checkpoint()
            sum += candles[i].close
            if (i >= period) {
                sum -= candles[i - period].close
            }
            if (i >= period - 1) {
                result.add(sum / period)
            } else {
                result.add(null)
            }
        }
        return result
    }

    /**
     * Exponential Moving Average (EMA)
     */
    fun calculateEma(candles: List<Candle>, period: Int, checkpoint: () -> Unit = {}): List<Double?> {
        checkpoint()
        if (candles.size < period) return List(candles.size) { if(it%1024==0) checkpoint(); null }
        val result = mutableListOf<Double?>()
        val multiplier = 2.0 / (period + 1)

        // Calculate initial SMA
        var sum = 0.0
        for (i in 0 until period) {
            if(i%1024==0) checkpoint()
            sum += candles[i].close
            result.add(null)
        }
        var prevEma = sum / period
        result[period - 1] = prevEma

        for (i in period until candles.size) {
            if(i%1024==0) checkpoint()
            val ema = (candles[i].close - prevEma) * multiplier + prevEma
            result.add(ema)
            prevEma = ema
        }
        return result
    }

    /**
     * Relative Strength Index (RSI)
     */
    fun calculateRsi(candles: List<Candle>, period: Int = 14, checkpoint: () -> Unit = {}): List<Double?> {
        checkpoint()
        if (candles.size <= period) return List(candles.size) { if(it%1024==0) checkpoint(); null }
        val result = mutableListOf<Double?>()

        for (i in 0..period) {
            if(i%1024==0) checkpoint()
            result.add(null)
        }

        var avgGain = 0.0
        var avgLoss = 0.0

        for (i in 1..period) {
            if(i%1024==0) checkpoint()
            val change = candles[i].close - candles[i - 1].close
            if (change > 0) avgGain += change else avgLoss += abs(change)
        }
        avgGain /= period
        avgLoss /= period

        val initialRs = if (avgLoss == 0.0) 100.0 else avgGain / avgLoss
        val initialRsi = if (avgLoss == 0.0) 100.0 else 100.0 - (100.0 / (1.0 + initialRs))
        result[period] = initialRsi

        for (i in (period + 1) until candles.size) {
            if(i%1024==0) checkpoint()
            val change = candles[i].close - candles[i - 1].close
            val gain = if (change > 0) change else 0.0
            val loss = if (change < 0) abs(change) else 0.0

            avgGain = (avgGain * (period - 1) + gain) / period
            avgLoss = (avgLoss * (period - 1) + loss) / period

            val rs = if (avgLoss == 0.0) 100.0 else avgGain / avgLoss
            val rsi = if (avgLoss == 0.0) 100.0 else 100.0 - (100.0 / (1.0 + rs))
            result.add(rsi)
        }

        return result
    }

    /**
     * Moving Average Convergence Divergence (MACD)
     */
    fun calculateMacd(
        candles: List<Candle>,
        fastPeriod: Int = 12,
        slowPeriod: Int = 26,
        signalPeriod: Int = 9,
        checkpoint: () -> Unit = {}
    ): List<MacdResult?> {
        checkpoint()
        val fastEma = calculateEma(candles, fastPeriod, checkpoint)
        val slowEma = calculateEma(candles, slowPeriod, checkpoint)
        val macdLine = mutableListOf<Double?>()

        for (i in candles.indices) {
            if(i%1024==0) checkpoint()
            val fast = fastEma[i]
            val slow = slowEma[i]
            if (fast != null && slow != null) {
                macdLine.add(fast - slow)
            } else {
                macdLine.add(null)
            }
        }

        // Calculate Signal line (EMA of MACD line)
        val signalMultiplier = 2.0 / (signalPeriod + 1)
        val validMacdIndices = macdLine.mapIndexedNotNull { index, v ->
            if(index%1024==0) checkpoint()
            if (v != null) Pair(index, v) else null
        }

        val result = MutableList<MacdResult?>(candles.size) { if(it%1024==0) checkpoint(); null }
        if (validMacdIndices.size < signalPeriod) return result

        var sum = 0.0
        for (i in 0 until signalPeriod) {
            if(i%1024==0) checkpoint()
            sum += validMacdIndices[i].second
        }
        var prevSignal = sum / signalPeriod
        val startIdx = validMacdIndices[signalPeriod - 1].first
        result[startIdx] = MacdResult(macdLine[startIdx]!!, prevSignal, macdLine[startIdx]!! - prevSignal)

        for (i in signalPeriod until validMacdIndices.size) {
            if(i%1024==0) checkpoint()
            val (idx, macdVal) = validMacdIndices[i]
            val signal = (macdVal - prevSignal) * signalMultiplier + prevSignal
            result[idx] = MacdResult(macdVal, signal, macdVal - signal)
            prevSignal = signal
        }

        return result
    }

    /**
     * Average True Range (ATR)
     */
    fun calculateAtr(candles: List<Candle>, period: Int = 14, checkpoint: () -> Unit = {}): List<Double?> {
        checkpoint()
        if (candles.size < period) return List(candles.size) { if(it%1024==0) checkpoint(); null }
        val result = mutableListOf<Double?>()

        val trueRanges = mutableListOf<Double>()
        for (i in candles.indices) {
            if(i%1024==0) checkpoint()
            if (i == 0) {
                trueRanges.add(candles[i].high - candles[i].low)
            } else {
                val tr = maxOf(
                    candles[i].high - candles[i].low,
                    abs(candles[i].high - candles[i - 1].close),
                    abs(candles[i].low - candles[i - 1].close)
                )
                trueRanges.add(tr)
            }
        }

        var sum = 0.0
        for (i in 0 until period) {
            if(i%1024==0) checkpoint()
            sum += trueRanges[i]
            result.add(null)
        }
        var prevAtr = sum / period
        result[period - 1] = prevAtr

        for (i in period until candles.size) {
            if(i%1024==0) checkpoint()
            val atr = (prevAtr * (period - 1) + trueRanges[i]) / period
            result.add(atr)
            prevAtr = atr
        }

        return result
    }

    /**
     * Bollinger Bands
     */
    fun calculateBollingerBands(
        candles: List<Candle>,
        period: Int = 20,
        stdDevMultiplier: Double = 2.0,
        checkpoint: () -> Unit = {}
    ): List<BollingerBandsResult?> {
        checkpoint()
        val sma = calculateSma(candles, period, checkpoint)
        val result = mutableListOf<BollingerBandsResult?>()

        for (i in candles.indices) {
            if(i%1024==0) checkpoint()
            val middle = sma[i]
            if (middle == null || i < period - 1) {
                result.add(null)
            } else {
                var varianceSum = 0.0
                for (j in (i - period + 1)..i) {
                    if(j%1024==0) checkpoint()
                    val diff = candles[j].close - middle
                    varianceSum += diff * diff
                }
                val stdDev = sqrt(varianceSum / period)
                val upper = middle + (stdDevMultiplier * stdDev)
                val lower = middle - (stdDevMultiplier * stdDev)
                result.add(BollingerBandsResult(middle, upper, lower))
            }
        }

        return result
    }

    /**
     * Volume Weighted Average Price (VWAP)
     */
    fun calculateVwap(candles: List<Candle>, checkpoint: () -> Unit = {}): List<Double> {
        checkpoint()
        val result = mutableListOf<Double>()
        var cumulativeTypicalPriceVolume = 0.0
        var cumulativeVolume = 0.0

        for ((index,candle) in candles.withIndex()) {
            if(index%1024==0) checkpoint()
            val typicalPrice = (candle.high + candle.low + candle.close) / 3.0
            val volume = if (candle.volume > 0) candle.volume else 1.0
            cumulativeTypicalPriceVolume += (typicalPrice * volume)
            cumulativeVolume += volume

            result.add(cumulativeTypicalPriceVolume / cumulativeVolume)
        }

        return result
    }
}
