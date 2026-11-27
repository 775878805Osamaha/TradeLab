import 'dart:math' as math;

import '../data/market_api.dart';
import '../data/tradelab_data.dart';
import 'chart_viewport.dart';

/// Derived exclusively from the supplied verified candles. [visibleCount]
/// prevents all future bars from leaking into replay labels.
abstract final class ChartAxisSourceLabels {
  static double? previousSessionClose(List<MarketBar> bars, int visibleCount) {
    final end = math.min(visibleCount, bars.length);
    if (end < 2) return null;
    final activeDay = DateTime.fromMillisecondsSinceEpoch(
      bars[end - 1].timestamp, isUtc: true);
    // The broker/cache contract guarantees strictly ascending UTC
    // timestamps. Find the first candle of the latest visible UTC day with
    // O(log N) source reads instead of scanning a full intraday session.
    // Replay must search ONLY [0, end): never inspect hidden future bars.
    final startOfDayMs =
        DateTime.utc(activeDay.year, activeDay.month, activeDay.day)
            .millisecondsSinceEpoch;
    var low = 0;
    var high = end;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (bars[middle].timestamp < startOfDayMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    // The candle immediately before midnight's first recorded bar is the
    // last authentic close of the previous session. Market holidays/gaps
    // must remain gaps: do not fabricate a midnight candle.
    return low == 0 ? null : bars[low - 1].candle.close;
  }

  /// Reuse the UNPADDED verified visible OHLC extrema already scanned by
  /// automatic chart scaling, but only when the label's source list is the
  /// exact same source as the painted candles and its visible bounds match.
  ///
  /// Heikin Ashi labels can intentionally refer to original OHLC rather
  /// than smoothed visual bars; manual ruler scales contain no source data.
  /// Both must continue using the original independent source scan.
  /// Replay prefixes must never reuse a live full-history price range.
  static (double, double)? visibleHighLowForPaint({
    required List<TradeCandle> source,
    required List<TradeCandle> displayed,
    required ChartPriceScale scale,
    required int start,
    required int end,
  }) {
    if (identical(source, displayed) &&
        identical(scale.sourceCandles, source) &&
        scale.sourceMinimum != null &&
        scale.sourceMaximum != null &&
        scale.sourceVisibleStart == start &&
        scale.sourceVisibleEnd == end) {
      return (scale.sourceMaximum!, scale.sourceMinimum!);
    }
    return visibleHighLow(source, start, end);
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
