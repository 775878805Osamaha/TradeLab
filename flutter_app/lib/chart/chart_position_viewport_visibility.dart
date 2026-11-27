import 'dart:math' as math;

import 'chart_short_position.dart';
import 'chart_viewport.dart';

/// The drawing rectangle and both price-axis labels use one source-index
/// visibility decision. Without it an old offscreen Long/Short still leaves
/// stop/target price tags on today's chart while its box is clipped away.
///
/// O(1) even for 100k+ verified candles. No source OHLC or Replay future
/// candles are accessed; only source bar indices and viewport geometry.
class ChartPositionViewportVisibility {
  const ChartPositionViewportVisibility._();

  static bool overlapsPlot({
    required ChartShortPosition position,
    required ChartViewport viewport,
    required int candleCount,
    required double plotWidth,
  }) {
    if (!position.visibleAt(candleCount) ||
        !plotWidth.isFinite || plotWidth <= 0 ||
        !viewport.barWidth.isFinite || viewport.barWidth <= 0 ||
        !viewport.scrollBars.isFinite ||
        !viewport.rightMarginBars.isFinite) return false;
    final first = viewport.chartX(
      index: position.startIndex,
      candleCount: candleCount,
      plotWidth: plotWidth,
    );
    final last = viewport.chartX(
      index: position.endIndex,
      candleCount: candleCount,
      plotWidth: plotWidth,
    );
    if (!first.isFinite || !last.isFinite) return false;
    return math.max(first, last) >= 0 &&
        math.min(first, last) <= plotWidth;
  }
}
