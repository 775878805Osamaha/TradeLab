import 'dart:math' as math;

/// A chart drawing, NOT an order. All prices are taken from chart gestures;
/// no position size, commission, account balance or monetary P/L is inferred.
class ChartShortPosition {
  const ChartShortPosition({
    required this.startIndex,
    required this.endIndex,
    required this.entry,
    required this.stop,
    required this.target,
  }) : assert(startIndex >= 0),
       assert(endIndex >= startIndex),
       assert(stop > entry),
       assert(entry > target);

  final int startIndex;
  final int endIndex;
  final double entry;
  final double stop;
  final double target;

  double get risk => stop - entry;
  double get reward => entry - target;
  double get riskPercent => risk / entry.abs() * 100;
  double get rewardPercent => reward / entry.abs() * 100;
  double get rewardRisk => reward / risk;

  /// A drawing's duration is in real visible bar indices, never screen pixels.
  ChartShortPosition shifted(int olderCount) => ChartShortPosition(
        startIndex: startIndex + olderCount,
        endIndex: endIndex + olderCount,
        entry: entry, stop: stop, target: target,
      );

  ChartShortPosition reanchored(int start, int end) => ChartShortPosition(
        startIndex: math.min(start, end),
        endIndex: math.max(start, end),
        entry: entry, stop: stop, target: target,
      );

  ChartShortPosition moved(int bars, double priceDelta) => ChartShortPosition(
        startIndex: startIndex + bars,
        endIndex: endIndex + bars,
        entry: entry + priceDelta,
        stop: stop + priceDelta,
        target: target + priceDelta,
      );

  /// Returns null if a handle would cross the entry level or a bar boundary.
  /// That keeps the sell tool meaningful without inventing a minimum stop.
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
        !(s > e && e > t) || from < 0 || to < from) return null;
    return ChartShortPosition(
      startIndex: from, endIndex: to, entry: e, stop: s, target: t,
    );
  }

  bool visibleAt(int revealedCount) =>
      startIndex < revealedCount && endIndex < revealedCount;
}

/// Hit testing and drawing share the exact same computed positions.
enum ShortPositionHandle { stop, entry, target, start, end, body }
