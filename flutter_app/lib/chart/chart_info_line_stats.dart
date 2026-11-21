import 'dart:math' as math;
import 'dart:ui';

import 'chart_annotations.dart';
import 'chart_price_text_formatter.dart';

/// TradingView-style Info Line statistics, derived solely from two genuine
/// price/bar anchors and the CURRENT displayed chart's UTC timestamps.
///
/// Never reads a full live archive when Replay has exposed only a prefix.
/// No broker prices, source indices or drawing anchors are ever rewritten.
class ChartInfoLineStats {
  const ChartInfoLineStats._({
    required this.priceChange,
    required this.percentChange,
    required this.bars,
    required this.elapsedMs,
    required this.angleDegrees,
  });

  final double priceChange;
  final double? percentChange;
  final int bars;
  final int elapsedMs;
  /// Angle is the actual displayed canvas line angle (not a synthetic
  /// market-price-to-calendar-duration angle).
  final double angleDegrees;

  static ChartInfoLineStats? fromVisible({
    required ChartPattern drawing,
    required int revealedCount,
    required List<int> timestampsUtcMs,
    required Offset startScreen,
    required Offset endScreen,
  }) {
    if (drawing.tool != ChartDrawingTool.infoLine ||
        revealedCount < 1 || !drawing.visibleAt(revealedCount)) {
      return null;
    }
    final first = drawing.start;
    final last = drawing.end;
    if (first.index < 0 || last.index < 0 ||
        first.index >= timestampsUtcMs.length ||
        last.index >= timestampsUtcMs.length ||
        !first.price.isFinite || !last.price.isFinite ||
        !startScreen.dx.isFinite || !startScreen.dy.isFinite ||
        !endScreen.dx.isFinite || !endScreen.dy.isFinite) return null;
    final firstUtc = timestampsUtcMs[first.index];
    final lastUtc = timestampsUtcMs[last.index];
    if (firstUtc <= 0 || lastUtc <= 0) return null;
    final delta = last.price - first.price;
    final pct = first.price == 0 ? null :
        delta / first.price.abs() * 100;
    final radians = math.atan2(
        startScreen.dy - endScreen.dy, endScreen.dx - startScreen.dx);
    final degrees = radians * 180 / math.pi;
    if (!delta.isFinite || !degrees.isFinite) return null;
    return ChartInfoLineStats._(
      priceChange: delta,
      percentChange: pct != null && pct.isFinite ? pct : null,
      bars: (last.index - first.index).abs(),
      elapsedMs: (lastUtc - firstUtc).abs(),
      angleDegrees: degrees,
    );
  }

  String get elapsedLabel {
    final mins = elapsedMs ~/ 60000;
    final days = mins ~/ (24 * 60);
    final hours = (mins ~/ 60) % 24;
    final minutes = mins % 60;
    if (days > 0) return '${days}ي ${hours}س ${minutes}د';
    if (hours > 0) return '${hours}س ${minutes}د';
    if (mins > 0) return '${mins}د';
    return '${(elapsedMs / 1000).toStringAsFixed(0)}ث';
  }

  String valueLabel(int digits) {
    final diff = ChartPriceTextFormatter.price(priceChange,
        digits.clamp(0, 12).toInt());
    final percent = percentChange == null
        ? '—' : '${percentChange!.toStringAsFixed(2)}%';
    return 'Δ $diff  ($percent)';
  }

  String get durationLabel =>
      '$bars شمعة · $elapsedLabel · ${angleDegrees.toStringAsFixed(1)}°';
}
