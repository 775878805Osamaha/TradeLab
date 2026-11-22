import 'dart:math' as math;
import 'dart:ui';

import 'chart_annotations.dart';
import 'chart_line_geometry.dart';

/// Paint-consistent hit testing for real source-anchored chart drawings.
///
/// Do not perform expensive price-axis transforms for historical finite
/// drawings which the painter already proved cannot intersect the plot.
/// Rays, extended lines, crosslines, Fibonacci levels and parallel channels
/// remain eligible even if their source anchors are far offscreen.
///
/// Works only with the caller's revealed Replay-prefix source indices;
/// does not request candles, generate timestamps or read future prices.
class ChartDrawingHitTest {
  const ChartDrawingHitTest._();

  static int? hit({
    required Offset position,
    required List<ChartPattern> patterns,
    required int revealedCount,
    required double plotWidth,
    required double plotHeight,
    required double Function(int sourceIndex) sourceX,
    required double Function(double marketPrice) sourceY,
    int? selectedPatternIndex,
    double touchRadius = 17,
  }) {
    // A touch on the ruler, bottom time axis or invalid pointer centroid
    // must not read/choose any source drawing.
    if (revealedCount <= 0 ||
        !position.dx.isFinite || !position.dy.isFinite ||
        !plotWidth.isFinite || plotWidth <= 0 ||
        !plotHeight.isFinite || plotHeight <= 0 ||
        !touchRadius.isFinite || touchRadius < 0 ||
        position.dx < 0 || position.dx >= plotWidth ||
        position.dy < 0 || position.dy >= plotHeight) {
      return null;
    }

    final plot = Rect.fromLTWH(0, 0, plotWidth, plotHeight);
    // Reverse order: most recently created/visually topmost drawing wins.
    for (var i = patterns.length - 1; i >= 0; i--) {
      final pattern = patterns[i];
      if (!pattern.visibleAt(revealedCount)) continue;

      final x1 = sourceX(pattern.start.index);
      final x2 = sourceX(pattern.end.index);
      // Match the painter's exact conservative x-rejection rule.
      // Never cull a selected drawing's handles or an unbounded shape.
      if (i != selectedPatternIndex &&
          ChartLineGeometry.definitelyOffscreenHorizontally(
            tool: pattern.tool, startX: x1, endX: x2,
            plotWidth: plotWidth)) {
        continue;
      }

      if (pattern.tool == ChartDrawingTool.fibonacci) {
        if (ChartLineGeometry.hitFibonacciLevels(
          point: position,
          fromX: math.min(x1, x2),
          levelYs: ChartPattern.fibonacciRatios.map(
              (ratio) => sourceY(pattern.fibonacciPrice(ratio))),
          plot: plot,
          touchRadius: touchRadius,
        )) return i;
        continue;
      }

      final y1 = sourceY(pattern.start.price);
      final y2 = sourceY(pattern.end.price);
      final anchor = pattern.offsetAnchor;
      final offset = anchor == null ? null : Offset(
        sourceX(anchor.index), sourceY(anchor.price));
      final strokes = ChartLineGeometry.strokes(
        tool: pattern.tool,
        start: Offset(x1, y1),
        end: Offset(x2, y2),
        offset: offset,
        bounds: plot,
      );
      for (final stroke in strokes) {
        if (ChartLineGeometry.distanceToStroke(position, stroke)
            <= touchRadius) return i;
      }
    }
    return null;
  }
}
