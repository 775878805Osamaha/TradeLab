import 'dart:math' as math;

import '../data/tradelab_data.dart';
import 'chart_indicator_engine.dart';
import 'chart_indicator_library.dart';
import 'chart_viewport.dart';

/// Extend a genuine candle-derived auto price scale to include any verified
/// visible price overlays (EMA, SMA and Bollinger), like TradingView's
/// "Scale price chart only" disabled default. Oscillator panes have their
/// own independent scales and are never mixed into price OHLC units.
///
/// This is presentation geometry only: broker highs/lows, source extrema,
/// crosshair market prices, drawing anchors, and all Replay trades remain
/// immutable. The base candle scale still owns fallback/offscreen handling.
class ChartIndicatorAutoScale {
  const ChartIndicatorAutoScale._();

  static ChartPriceScale include({
    required ChartPriceScale base,
    required List<TradeCandle> candles,
    required ChartViewport viewport,
    required double plotWidth,
    required Iterable<ChartIndicatorDefinition> indicators,
    required ChartIndicatorSeriesCache cache,
  }) {
    if (candles.isEmpty) return base;
    final overlays = indicators.where((item) => !item.separatePane).toList();
    if (overlays.isEmpty) return base;
    final (start, end) = viewport.visibleIndices(
        plotWidth: plotWidth, candleCount: candles.length);
    if (start >= end) return base;
    var minimum = base.minimum;
    var maximum = base.maximum;
    for (final item in overlays) {
      final result = cache.get(candles, item);
      for (final plot in result.plots) {
        for (var i = start; i < end; i++) {
          final value = plot.values[i];
          if (value == null || !value.isFinite ||
              (base.usesLogarithmic && value <= 0)) continue;
          minimum = math.min(minimum, value);
          maximum = math.max(maximum, value);
        }
      }
    }
    if (minimum == base.minimum && maximum == base.maximum) return base;
    final margin = math.max((maximum - minimum) * .018,
        math.max(maximum.abs(), minimum.abs()) * 1e-8);
    final nextMin = minimum - margin;
    final nextMax = maximum + margin;
    final lower = base.usesLogarithmic
        ? math.max(double.minPositive, nextMin) : nextMin;
    return ChartPriceScale(lower, nextMax, base.height,
      sourceCandles: base.sourceCandles,
      sourceMinimum: base.sourceMinimum,
      sourceMaximum: base.sourceMaximum,
      sourceVisibleStart: base.sourceVisibleStart,
      sourceVisibleEnd: base.sourceVisibleEnd,
      logarithmic: base.logarithmic,
      inverted: base.inverted,
      referenceMode: base.referenceMode,
      referencePrice: base.referencePrice);
  }
}
