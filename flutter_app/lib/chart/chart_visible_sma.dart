import '../data/tradelab_data.dart';

/// The SMA label on the price axis must describe the last bar ACTUALLY
/// rendered in the current chart viewport, not the newest broker bar in the
/// entire archive. In Replay the same exclusive bound prevents querying any
/// hidden future candle beyond the selected historical cutoff.
///
/// Uses the same 12-period warm-up convention as the chart's SMA line:
/// while fewer than 12 source candles are available, divide by their count.
/// Does not generate or alter any market data.
class ChartVisibleSma {
  const ChartVisibleSma._();

  static double? atVisibleEnd(List<TradeCandle> candles,
      int endExclusive, {int period = 12}) {
    if (period <= 0) {
      throw ArgumentError.value(period, 'period', 'Must be positive');
    }
    if (endExclusive < 1 || endExclusive > candles.length) return null;

    final count = endExclusive < period ? endExclusive : period;
    var total = 0.0;
    for (var i = endExclusive - count; i < endExclusive; i++) {
      total += candles[i].close;
    }
    return total / count;
  }
}
