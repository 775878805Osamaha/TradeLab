import 'dart:math' as math;

enum ChartPositionDirection { short, long }

/// A chart drawing, NOT an order. All prices are taken from chart gestures;
/// no position size, commission, account balance or monetary P/L is inferred.
class ChartShortPosition {
  const ChartShortPosition({
    required this.startIndex,
    required this.endIndex,
    required this.entry,
    required this.stop,
    required this.target,
    this.direction = ChartPositionDirection.short,
  }) : assert(startIndex >= 0),
       assert(endIndex >= startIndex),
       assert(direction == ChartPositionDirection.short
           ? stop > entry && entry > target
           : stop < entry && entry < target);

  final int startIndex;
  final int endIndex;
  final double entry;
  final double stop;
  final double target;
  /// Legacy class name retained for compatibility with existing drawing
  /// data; both sides are chart annotations, never actual broker orders.
  final ChartPositionDirection direction;
  bool get isLong => direction == ChartPositionDirection.long;

  double get risk => isLong ? entry - stop : stop - entry;
  double get reward => isLong ? target - entry : entry - target;
  double get riskPercent => risk / entry.abs() * 100;
  double get rewardPercent => reward / entry.abs() * 100;
  double get rewardRisk => reward / risk;

  /// A drawing's duration is in real visible bar indices, never screen pixels.
  ChartShortPosition shifted(int olderCount) => ChartShortPosition(
        startIndex: startIndex + olderCount,
        endIndex: endIndex + olderCount,
        entry: entry, stop: stop, target: target,
        direction: direction,
      );

  ChartShortPosition reanchored(int start, int end) => ChartShortPosition(
        startIndex: math.min(start, end),
        endIndex: math.max(start, end),
        entry: entry, stop: stop, target: target,
        direction: direction,
      );

  ChartShortPosition moved(int bars, double priceDelta) => ChartShortPosition(
        startIndex: startIndex + bars,
        endIndex: endIndex + bars,
        entry: entry + priceDelta,
        stop: stop + priceDelta,
        target: target + priceDelta,
        direction: direction,
      );

  /// Returns null if a handle crosses entry, flips the chosen direction or
  /// changes the source bar order. Long stop is below entry; short above.
  ChartShortPosition? edited({
    double? stop,
    double? entry,
    double? target,
    int? startIndex,
    int? endIndex,
  }) {
    final s = stop ?? this.stop;
    final e = entry ?? this.entry;
    final t = target ?? this.target;
    final from = startIndex ?? this.startIndex;
    final to = endIndex ?? this.endIndex;
    if (![s, e, t].every((v) => v.isFinite && v > 0) ||
        !(isLong ? s < e && e < t : s > e && e > t) ||
        from < 0 || to < from) return null;
    return ChartShortPosition(
      startIndex: from, endIndex: to, entry: e, stop: s, target: t,
      direction: direction,
    );
  }

  bool visibleAt(int revealedCount) =>
      startIndex < revealedCount && endIndex < revealedCount;
}

/// Hit testing and drawing share the exact same computed positions.
enum ShortPositionHandle { stop, entry, target, start, end, body }
