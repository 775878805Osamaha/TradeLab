import 'market_api.dart';
import 'range_bar_timeline.dart';

/// A contiguous, source-verified set of BID ticks used to draw Range bars.
/// The loader requests short, disjoint intervals newest first. It never
/// derives ticks from OHLC, fills gaps, or accepts incomplete gateway pages.
class RangeStartupSnapshot {
  const RangeStartupSnapshot(this.fromMs, this.toMs, this.ticks, this.timeline);

  final int fromMs;
  final int toMs;
  final List<MarketTick> ticks;
  final RangeBarTimeline timeline;

  int get closedBars => timeline.bars.isEmpty ? 0 : timeline.bars.length - 1;
}

class RangeStartupLoader {
  // Cumulative lookback horizons. The former six-day, all-at-once request
  // could require thousands of network pages before any candle appeared.
  // This bounded startup makes the first verified tick slice visible early.
  static const horizons = <Duration>[
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
    Duration(hours: 4),
    Duration(hours: 12),
    Duration(hours: 24),
    Duration(days: 3),
    Duration(days: 6),
  ];
  static const maxStartupTicks = 1000000;

  /// [getTicks] must return an ordered, complete and verified cTrader BID
  /// response for the *inclusive* requested interval. Adjacent windows never
  /// overlap, even when the broker has multiple ticks at one millisecond.
  static Future<RangeStartupSnapshot?> load({
    required int endMs,
    required double priceDistance,
    required Future<List<MarketTick>> Function(int fromMs, int toMs) getTicks,
    required Future<void> Function(RangeStartupSnapshot) onSnapshot,
    int minimumClosedBars = 12,
  }) async {
    if (endMs <= horizons.last.inMilliseconds ||
        !priceDistance.isFinite || priceDistance <= 0 ||
        minimumClosedBars < 1) {
      throw ArgumentError('Invalid Range startup bounds');
    }

    var priorFrom = endMs + 1;
    var combined = <MarketTick>[];
    RangeStartupSnapshot? latest;
    for (final horizon in horizons) {
      final fromMs = endMs - horizon.inMilliseconds;
      final toMs = priorFrom - 1;
      final page = await getTicks(fromMs, toMs);
      var previous = fromMs;
      for (final tick in page) {
        if (tick.timestamp < previous || tick.timestamp > toMs ||
            !tick.bid.isFinite || tick.bid <= 0) {
          throw const MarketDataException(
              'تيكات cTrader لا تتوافق مع النوافذ الزمنية المطلوبة.');
        }
        previous = tick.timestamp;
      }
      if (combined.length + page.length > maxStartupTicks) {
        throw const MarketDataException(
            'تاريخ cTrader أكبر من الحد الآمن للذاكرة. '
            'اختر مدى أكبر أو حدّث بيانات الوسيط.');
      }
      combined = <MarketTick>[...page, ...combined];
      priorFrom = fromMs;
      if (combined.isEmpty) continue;

      final timeline = await RangeBarTimeline.buildAsync(
          combined, priceDistance);
      latest = RangeStartupSnapshot(
          fromMs, endMs, List<MarketTick>.unmodifiable(combined), timeline);
      await onSnapshot(latest);
      if (latest.closedBars >= minimumClosedBars) break;
    }
    return latest;
  }
}
