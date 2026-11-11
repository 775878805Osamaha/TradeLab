import 'dart:math' as math;

import '../data/market_api.dart';
import '../data/tradelab_data.dart';

/// Derived exclusively from the supplied verified candles. [visibleCount]
/// prevents all future bars from leaking into replay labels.
abstract final class ChartAxisSourceLabels {
  static double? previousSessionClose(List<MarketBar> bars, int visibleCount) {
    final end = math.min(visibleCount, bars.length);
    if (end < 2) return null;
    final activeDay = DateTime.fromMillisecondsSinceEpoch(
      bars[end - 1].timestamp, isUtc: true);
    for (var i = end - 2; i >= 0; i--) {
      final stamp = DateTime.fromMillisecondsSinceEpoch(
        bars[i].timestamp, isUtc: true);
      if (stamp.year != activeDay.year || stamp.month != activeDay.month ||
          stamp.day != activeDay.day) {
        return bars[i].candle.close;
      }
    }
    return null;
  }

  static (double, double)? visibleHighLow(
    List<TradeCandle> actual, int start, int end) {
    if (actual.isEmpty || start >= end || start < 0) return null;
    final through = math.min(end, actual.length);
    if (start >= through) return null;
    var high = actual[start].high;
    var low = actual[start].low;
    for (var i = start + 1; i < through; i++) {
      high = math.max(high, actual[i].high);
      low = math.min(low, actual[i].low);
    }
    return (high, low);
  }
}
