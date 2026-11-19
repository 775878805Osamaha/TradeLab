import 'dart:math' as math;
import 'dart:ui';

import 'chart_annotations.dart';

typedef ChartStroke = ({Offset start, Offset end});

/// Source-anchored drawing geometry, converted to the same viewport used by
/// the market candles. This module never invents OHLC or future chart points.
class ChartLineGeometry {
  const ChartLineGeometry._();

  static List<ChartStroke> strokes({
    required ChartDrawingTool tool,
    required Offset start,
    required Offset end,
    required Rect bounds,
    Offset? offset,
  }) {
    ChartStroke? segment(Offset a, Offset b,
        {double low = 0, double high = 1}) {
      final direction = b - a;
      if (direction.distanceSquared < 1e-10) return null;
      var minT = low;
      var maxT = high;
      bool clip(double p, double q) {
        if (p.abs() < 1e-10) return q >= 0;
        final t = q / p;
        if (p < 0) {
          minT = math.max(minT, t);
        } else {
          maxT = math.min(maxT, t);
        }
        return minT <= maxT;
      }
      if (!clip(-direction.dx, a.dx - bounds.left) ||
          !clip(direction.dx, bounds.right - a.dx) ||
          !clip(-direction.dy, a.dy - bounds.top) ||
          !clip(direction.dy, bounds.bottom - a.dy)) return null;
      return (start: a + direction * minT, end: a + direction * maxT);
    }

    if (tool == ChartDrawingTool.verticalLine) {
      final stroke = segment(start, start + const Offset(0, 1),
          low: double.negativeInfinity, high: double.infinity);
      return stroke == null ? [] : [stroke];
    }
    if (tool == ChartDrawingTool.horizontalRay) {
      final stroke = segment(start, start + const Offset(1, 0),
          high: double.infinity);
      return stroke == null ? [] : [stroke];
    }
    if (tool == ChartDrawingTool.ray ||
        tool == ChartDrawingTool.extendedLine) {
      final stroke = segment(start, end,
          low: tool == ChartDrawingTool.ray ? 0 : double.negativeInfinity,
          high: double.infinity);
      return stroke == null ? [] : [stroke];
    }
    if (tool == ChartDrawingTool.parallelChannel && offset != null) {
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      final displacement = dx.abs() > 1e-8
          ? Offset(0, offset.dy - (start.dy +
              dy * (offset.dx - start.dx) / dx))
          : Offset(offset.dx - start.dx, 0);
      final original = segment(start, end);
      final parallel = segment(
          start + displacement, end + displacement);
      return [
        if (original != null) original,
        if (parallel != null) parallel,
      ];
    }
    final stroke = segment(start, end);
    return stroke == null ? [] : [stroke];
  }

  /// Visible portion of a Fibonacci level. A first anchor can be far left
  /// of the screen while its level still spans the current chart.
  /// Geometry only: never manufacture future bars or modify broker prices.
  static ChartStroke? fibonacciLevelStroke({
    required double fromX,
    required double levelY,
    required Rect plot,
  }) {
    if (!fromX.isFinite || !levelY.isFinite ||
        !plot.left.isFinite || !plot.right.isFinite ||
        !plot.top.isFinite || !plot.bottom.isFinite ||
        plot.width <= 0 || plot.height <= 0 ||
        fromX >= plot.right ||
        levelY < plot.top || levelY > plot.bottom) {
      return null;
    }
    return (
      start: Offset(math.max(fromX, plot.left), levelY),
      end: Offset(plot.right, levelY),
    );
  }

  /// Select only the Fibonacci levels the candle canvas actually paints.
  /// An invisible ratio outside the current price range must not steal a
  /// touch from candle pan or a neighboring drawing near the plot edge.
  static bool hitFibonacciLevels({
    required Offset point,
    required double fromX,
    required Iterable<double> levelYs,
    required Rect plot,
    double touchRadius = 17,
  }) {
    if (!point.dx.isFinite || !point.dy.isFinite ||
        !touchRadius.isFinite || touchRadius < 0 ||
        !plot.contains(point)) {
      return false;
    }
    for (final levelY in levelYs) {
      final visibleStroke = fibonacciLevelStroke(
        fromX: fromX, levelY: levelY, plot: plot);
      if (visibleStroke != null &&
          distanceToStroke(point, visibleStroke) <= touchRadius) {
        return true;
      }
    }
    return false;
  }

  /// Draw the TradingView-style dashed last-close guide with one Canvas
  /// drawPath instead of dozens of individual drawLine calls per frame.
  /// Keep the existing 6px interval and 2.2px dash length exactly, with
  /// the final dash clipped to the candle plot (not the right price ruler).
  /// This is paint-only geometry: the broker close is never changed.
  static Path lastCloseDashPath({
    required double y,
    required double plotWidth,
  }) {
    final path = Path();
    if (!y.isFinite || !plotWidth.isFinite || plotWidth <= 0) {
      return path;
    }
    for (var x = 0.0; x < plotWidth; x += 6) {
      path.moveTo(x, y);
      path.lineTo(math.min(plotWidth, x + 2.2), y);
    }
    return path;
  }

  static double distanceToStroke(Offset point, ChartStroke stroke) {
    final d = stroke.end - stroke.start;
    final magnitude = d.distanceSquared;
    if (magnitude < 1e-10) return (point - stroke.start).distance;
    final projection = ((point - stroke.start).dx * d.dx +
            (point - stroke.start).dy * d.dy) /
        magnitude;
    final t = projection.clamp(0.0, 1.0);
    return (point - (stroke.start + d * t)).distance;
  }
}
