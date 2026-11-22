import 'dart:math' as math;

import 'chart_viewport.dart';

/// TradingView-like mobile time-axis ticks stay attached to REAL source
/// candle columns while a finger drags or pinches the chart. Screen-fixed
/// x = width * fraction labels were visually detached from candles: the
/// displayed time jumped while the vertical ruler remained motionless.
///
/// This is a *presentation* index selector, not a market-data calendar:
/// it cannot add bars inside weekend gaps, infer cTrader timestamps,
/// advance Replay's confirmed prefix, or alter OHLC/BID ordering.
/// Renderers read the timestamp of each returned authentic source index.
class ChartSourceTimeGrid {
  const ChartSourceTimeGrid._();

  static const minTickSpacingPx = 84.0;
  static const maxVisibleMarks = 16;

  /// Round up to a visually familiar 1 / 2 / 5 / 10 interval.
  /// At 3px/bar this is O(1) even for 100k+ source candles.
  static int niceBarStep(int minimumBars) {
    if (minimumBars <= 1) return 1;
    var magnitude = 1;
    // The maximum index space supported by historical market snapshots is
    // vastly smaller than this guard. Never multiply out of integer range.
    while (magnitude < 100000000 && magnitude * 10 < minimumBars) {
      magnitude *= 10;
    }
    for (final factor in const [1, 2, 5, 10]) {
      final candidate = magnitude * factor;
      if (candidate >= minimumBars) return candidate;
    }
    return magnitude * 10;
  }

  /// Index zero is an intentional stable grid phase. A source bar keeps its
  /// x-coordinate throughout smooth sub-candle panning; ticks move WITH it.
  ///
  /// Snapping to indices instead of arbitrary screen pixels also means
  /// sparse/irregular cTrader Range bars use their REAL BID timestamps
  /// supplied by the caller, not fabricated clock intervals.
  static List<({int index, double x})> visible({
    required ChartViewport viewport,
    required double plotWidth,
    required int candleCount,
  }) {
    if (candleCount <= 0 || !plotWidth.isFinite || plotWidth <= 0 ||
        !viewport.barWidth.isFinite || viewport.barWidth <= 0 ||
        !viewport.scrollBars.isFinite ||
        !viewport.rightMarginBars.isFinite) {
      return const [];
    }
    final (first, exclusiveEnd) = viewport.visibleIndices(
        plotWidth: plotWidth, candleCount: candleCount);
    if (first >= exclusiveEnd) return const [];
    final minimumBars =
        math.max(1, (minTickSpacingPx / viewport.barWidth).ceil());
    final step = niceBarStep(minimumBars);
    var index = first + (step - first % step) % step;
    final positions = <({int index, double x})>[];
    while (index < exclusiveEnd && positions.length < maxVisibleMarks) {
      final x = viewport.chartX(index: index,
          candleCount: candleCount, plotWidth: plotWidth);
      if (x.isFinite && x >= 0 && x < plotWidth) {
        positions.add((index: index, x: x));
      }
      index += step;
    }
    return positions;
  }
}
