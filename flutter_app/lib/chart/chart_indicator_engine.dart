import 'dart:math' as math;
import 'dart:collection';

import '../data/tradelab_data.dart';
import 'chart_indicator_library.dart';
import 'pine_subset_program.dart';

/// Exact source-indexed indicator output; unsupported scripts never reach it.
class ChartIndicatorPlot {
  const ChartIndicatorPlot(this.title, this.values,
      {this.histogram = false, this.argbColor, this.width = 2});
  final String title;
  final List<double?> values;
  final bool histogram;
  final int? argbColor;
  final int width;
}

class ChartIndicatorOutput {
  const ChartIndicatorOutput(this.indicator, this.plots);
  final ChartIndicatorDefinition indicator;
  final List<ChartIndicatorPlot> plots;
}

/// Cache one immutable broker/Replay prefix per chart. Gestures only read
/// viewport slices. A source identity or cutoff change resets cached values.
class ChartIndicatorSeriesCache {
  List<TradeCandle>? _source;
  int? _length;
  final Map<String, ChartIndicatorOutput> _outputs = {};

  ChartIndicatorOutput get(
      List<TradeCandle> candles, ChartIndicatorDefinition indicator) {
    if (!identical(candles, _source) || _length != candles.length) {
      _source = candles;
      _length = candles.length;
      _outputs.clear();
    }
    final key = indicator.id + ':' + indicator.kind.name +
        ':' + indicator.period.toString() +
        ':' + (indicator.pineSource ?? '') +
        ':' + indicator.pineOverlay.toString();
    return _outputs.putIfAbsent(
        key, () => ChartIndicatorEngine.compute(candles, indicator));
  }

  void clear() {
    _source = null;
    _length = null;
    _outputs.clear();
  }
}

/// Genuine close/OHLC calculations. This is NOT arbitrary Pine execution.
/// EMA: first close seed, alpha 2/(period+1).
/// BB: SMA basis, population deviation *2.
/// RSI: Wilder average gain/loss, period-delta initial SMA.
/// MACD: EMA(12)-EMA(26), EMA(9) signal, oscillator histogram.
/// ATR: Wilder RMA of true range, first-period SMA seed.
class ChartIndicatorEngine {
  const ChartIndicatorEngine._();

  static List<double?> ema(List<double> source, int period) {
    final output = List<double?>.filled(source.length, null);
    if (period < 1 || period > 500 || source.isEmpty) return output;
    final alpha = 2.0 / (period + 1);
    var last = source.first;
    output[0] = last;
    for (var i = 1; i < source.length; i++) {
      last = alpha * source[i] + (1 - alpha) * last;
      output[i] = last;
    }
    return output;
  }

  static List<double?> _sma(List<double> close, int period) {
    final output = List<double?>.filled(close.length, null);
    var sum = 0.0;
    for (var i = 0; i < close.length; i++) {
      sum += close[i];
      if (i >= period) sum -= close[i - period];
      // TradingView ta.sma emits na until a full period of closes.
      if (i >= period - 1) output[i] = sum / period;
    }
    return output;
  }

  static List<ChartIndicatorPlot> _bollinger(
      List<double> close, int period) {
    final basis = List<double?>.filled(close.length, null);
    final high = List<double?>.filled(close.length, null);
    final low = List<double?>.filled(close.length, null);
    var sum = 0.0;
    var sumSquared = 0.0;
    // Center before summing squares to avoid cancellation on high-price
    // symbols with tiny genuine band deviations (e.g. 3000.01).
    final origin = close.isEmpty ? 0.0 : close.first;
    for (var i = 0; i < close.length; i++) {
      final value = close[i] - origin;
      sum += value;
      sumSquared += value * value;
      if (i >= period) {
        final removed = close[i - period] - origin;
        sum -= removed;
        sumSquared -= removed * removed;
      }
      if (i < period - 1) continue;
      final centeredMean = sum / period;
      final middle = origin + centeredMean;
      final variance = math.max(0.0,
          sumSquared / period - centeredMean * centeredMean);
      final deviation = 2 * math.sqrt(variance);
      basis[i] = middle;
      high[i] = middle + deviation;
      low[i] = middle - deviation;
    }
    return [
      ChartIndicatorPlot('Basis', basis),
      ChartIndicatorPlot('Upper', high),
      ChartIndicatorPlot('Lower', low),
    ];
  }

  static List<double?> _rsi(List<double> close, int period) {
    final result = List<double?>.filled(close.length, null);
    if (close.length <= period) return result;
    var upSum = 0.0;
    var downSum = 0.0;
    for (var i = 1; i <= period; i++) {
      final change = close[i] - close[i - 1];
      upSum += math.max(0, change);
      downSum += math.max(0, -change);
    }
    var averageUp = upSum / period;
    var averageDown = downSum / period;
    double value() {
      if (averageDown == 0) {
        // The built-in TradingView RSI resolves a zero loss average to
        // 100, including the fully flat 0/0 case. Returning 50 here
        // silently disagrees with the standard built-in Pine script.
        return 100.0;
      }
      if (averageUp == 0) return 0.0;
      return 100 - 100 / (1 + averageUp / averageDown);
    }
    result[period] = value();
    for (var i = period + 1; i < close.length; i++) {
      final change = close[i] - close[i - 1];
      averageUp = (averageUp * (period - 1) + math.max(0, change)) / period;
      averageDown =
          (averageDown * (period - 1) + math.max(0, -change)) / period;
      result[i] = value();
    }
    return result;
  }

  static List<ChartIndicatorPlot> _macd(List<double> close) {
    final fast = ema(close, 12);
    final slow = ema(close, 26);
    final macd = List<double>.generate(
        close.length, (i) => fast[i]! - slow[i]!);
    final signal = ema(macd, 9);
    final histogram = List<double?>.generate(
        close.length, (i) => macd[i] - signal[i]!);
    return [
      ChartIndicatorPlot('MACD', macd),
      ChartIndicatorPlot('Signal', signal),
      ChartIndicatorPlot('Histogram', histogram, histogram: true),
    ];
  }


  /// TradingView ROC: 100*(currentClose / close[period] - 1).
  /// Do not invent a rate when the real historical denominator is zero.
  static List<double?> _roc(List<double> close, int period) {
    final result = List<double?>.filled(close.length, null);
    for (var i = period; i < close.length; i++) {
      final previous = close[i - period];
      if (previous == 0) continue;
      final value = 100 * (close[i] - previous) / previous;
      if (value.isFinite) result[i] = value;
    }
    return result;
  }

  /// The built-in TradingView Stochastic is:
  /// rawK = 100*(close - lowest(low,periodK)) /
  ///                 (highest(high,periodK)-lowest(low,periodK));
  /// K = SMA(rawK, 3), D = SMA(K, 3).
  /// Monotonic deques compute extremes O(source length), even with
  /// large user-selected lengths (up to 500) and 100k+ real bars.
  static List<ChartIndicatorPlot> _stochastic(
      List<TradeCandle> candles, int period) {
    final smoothK = List<double?>.filled(candles.length, null);
    final smoothD = List<double?>.filled(candles.length, null);
    final highIndices = ListQueue<int>();
    final lowIndices = ListQueue<int>();
    var rawSum = 0.0;
    var rawCount = 0;
    var smoothedSum = 0.0;
    var smoothedCount = 0;
    final rawRing = List<double>.filled(3, 0);
    final kRing = List<double>.filled(3, 0);
    for (var i = 0; i < candles.length; i++) {
      final high = candles[i].high;
      final low = candles[i].low;
      while (highIndices.isNotEmpty &&
          candles[highIndices.last].high <= high) {
        highIndices.removeLast();
      }
      highIndices.addLast(i);
      while (lowIndices.isNotEmpty &&
          candles[lowIndices.last].low >= low) {
        lowIndices.removeLast();
      }
      lowIndices.addLast(i);
      final oldest = i - period + 1;
      while (highIndices.isNotEmpty && highIndices.first < oldest) {
        highIndices.removeFirst();
      }
      while (lowIndices.isNotEmpty && lowIndices.first < oldest) {
        lowIndices.removeFirst();
      }
      if (i < period - 1) continue;
      final highest = candles[highIndices.first].high;
      final lowest = candles[lowIndices.first].low;
      final span = highest - lowest;
      if (span <= 0 || !span.isFinite) {
        rawCount = 0;
        rawSum = 0;
        smoothedCount = 0;
        smoothedSum = 0;
        continue;
      }
      final raw = 100 * (candles[i].close - lowest) / span;
      if (!raw.isFinite) continue;
      final rawSlot = rawCount % 3;
      if (rawCount >= 3) rawSum -= rawRing[rawSlot];
      rawRing[rawSlot] = raw;
      rawSum += raw;
      rawCount++;
      if (rawCount < 3) continue;
      final k = rawSum / 3;
      smoothK[i] = k;
      final kSlot = smoothedCount % 3;
      if (smoothedCount >= 3) smoothedSum -= kRing[kSlot];
      kRing[kSlot] = k;
      smoothedSum += k;
      smoothedCount++;
      if (smoothedCount >= 3) smoothD[i] = smoothedSum / 3;
    }
    return [
      ChartIndicatorPlot('%K', smoothK),
      ChartIndicatorPlot('%D', smoothD),
    ];
  }

  static List<double?> _atr(List<TradeCandle> candles, int period) {
    final values = List<double?>.filled(candles.length, null);
    if (candles.isEmpty) return values;
    var initial = 0.0;
    var last = 0.0;
    for (var i = 0; i < candles.length; i++) {
      final bar = candles[i];
      final trueRange = i == 0
          ? bar.high - bar.low
          : math.max(bar.high - bar.low,
              math.max((bar.high - candles[i - 1].close).abs(),
                  (bar.low - candles[i - 1].close).abs()));
      if (i < period) {
        initial += trueRange;
        if (i == period - 1) {
          last = initial / period;
          values[i] = last;
        }
      } else {
        last = (last * (period - 1) + trueRange) / period;
        values[i] = last;
      }
    }
    return values;
  }

  static ChartIndicatorOutput compute(
      List<TradeCandle> candles, ChartIndicatorDefinition indicator) {
    final length = indicator.period;
    if (length < 1 || length > 500 ||
        (indicator.kind == ChartIndicatorKind.rsi && length < 2)) {
      return ChartIndicatorOutput(indicator, const []);
    }
    // Replay CandlePrefix clamps all reads to already-revealed bars.
    final close = List<double>.generate(
        candles.length, (i) => candles[i].close, growable: false);
    final plots = switch (indicator.kind) {
      ChartIndicatorKind.sma =>
        [ChartIndicatorPlot('SMA', _sma(close, length))],
      ChartIndicatorKind.ema =>
        [ChartIndicatorPlot('EMA', ema(close, length))],
      ChartIndicatorKind.bollinger => _bollinger(close, length),
      ChartIndicatorKind.rsi =>
        [ChartIndicatorPlot('RSI', _rsi(close, length))],
      ChartIndicatorKind.macd => _macd(close),
      ChartIndicatorKind.atr =>
        [ChartIndicatorPlot('ATR', _atr(candles, length))],
      ChartIndicatorKind.stochastic => _stochastic(candles, length),
      ChartIndicatorKind.roc =>
        [ChartIndicatorPlot('ROC', _roc(close, length))],
      ChartIndicatorKind.pine => [
        for (final plot in PineSubsetProgram.compile(
            indicator.pineSource!).evaluate(candles))
          ChartIndicatorPlot(plot.title, plot.values,
              histogram: plot.histogram,
              argbColor: plot.argbColor, width: plot.width),
      ],
    };
    return ChartIndicatorOutput(indicator, plots);
  }
}
