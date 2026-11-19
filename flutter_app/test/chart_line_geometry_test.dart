import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_annotations.dart';
import 'package:tradelab_flutter/chart/chart_line_geometry.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  const bounds = Rect.fromLTWH(0, 0, 100, 100);
  const start = Offset(20, 80);
  const end = Offset(60, 40);

  test('historical Fibonacci level and its label start inside viewport', () {
    // The original first anchor can be 4000px left after panning.
    // Its real ratio/price level still runs across today's visible chart.
    final level = ChartLineGeometry.fibonacciLevelStroke(
      fromX: -4000, levelY: 45, plot: bounds);
    expect(level, isNotNull);
    expect(level!.start, const Offset(0, 45));
    expect(level.end, const Offset(100, 45));
    // Before the fix the painter placed the label at x=-3995.
    expect(level.start.dx + 5, inInclusiveRange(0, 100));

    final partlyVisible = ChartLineGeometry.fibonacciLevelStroke(
      fromX: 38.5, levelY: 72, plot: bounds);
    expect(partlyVisible?.start, const Offset(38.5, 72));
    expect(partlyVisible?.end, const Offset(100, 72));
  });

  test('Fibonacci culls offscreen levels without altering real prices', () {
    const selected = ChartPattern(
      tool: ChartDrawingTool.fibonacci,
      start: ChartAnchor(20, 1925),
      end: ChartAnchor(35, 1975),
    );
    expect(selected.fibonacciPrice(.618), closeTo(1955.9, 1e-9));
    expect(selected.visibleAt(36), isTrue);
    expect(selected.visibleAt(35), isFalse,
      reason: 'Replay cannot show levels anchored to unrevealed bars');

    expect(ChartLineGeometry.fibonacciLevelStroke(
      fromX: 101, levelY: 50, plot: bounds), isNull,
      reason: 'No line or text belongs to a future/off-right screen anchor');
    expect(ChartLineGeometry.fibonacciLevelStroke(
      fromX: -3000, levelY: 101, plot: bounds), isNull);
    expect(ChartLineGeometry.fibonacciLevelStroke(
      fromX: -3000, levelY: -1, plot: bounds), isNull);
    expect(selected.fibonacciPrice(.618), closeTo(1955.9, 1e-9));
  });

  test('Fibonacci clipping is finite, bounded, and preserves plot edges', () {
    const plot = Rect.fromLTWH(10, 12, 250, 180);
    expect(ChartLineGeometry.fibonacciLevelStroke(
      fromX: -9000000, levelY: 12, plot: plot)?.start,
      const Offset(10, 12));
    expect(ChartLineGeometry.fibonacciLevelStroke(
      fromX: 15, levelY: 192, plot: plot)?.end,
      const Offset(260, 192));
    for (final invalid in [double.nan, double.infinity,
      double.negativeInfinity]) {
      expect(ChartLineGeometry.fibonacciLevelStroke(
        fromX: invalid, levelY: 100, plot: plot), isNull);
      expect(ChartLineGeometry.fibonacciLevelStroke(
        fromX: 0, levelY: invalid, plot: plot), isNull);
    }
    expect(ChartLineGeometry.fibonacciLevelStroke(
      fromX: 0, levelY: 100, plot: Rect.zero), isNull);
    expect(ChartLineGeometry.fibonacciLevelStroke(
      fromX: 0, levelY: 100,
      plot: const Rect.fromLTWH(0, 0, 100, 0)), isNull);
  });

  test('Fibonacci hit detects only the level actually visible in 320dp chart', () {
    // A 320dp Android screen has a 259dp plot and a separate price ruler.
    const plot = Rect.fromLTWH(0, 0, 259, 400);
    const levels = <double>[-8, 120, 408];
    bool hit(Offset point, {double from = -2000}) =>
        ChartLineGeometry.hitFibonacciLevels(
          point: point, fromX: from, levelYs: levels, plot: plot);

    expect(hit(const Offset(100, 0)), isFalse,
        reason: 'Previously y=-8 was touch-selectable at y=0 despite being hidden');
    expect(hit(const Offset(100, 399)), isFalse,
        reason: 'Previously y=408 could steal a touch near lower chart edge');
    expect(hit(const Offset(100, 120)), isTrue);
    expect(hit(const Offset(100, 133)), isTrue,
        reason: 'Preserve accessible 17px hit radius around a visible line');
    expect(hit(const Offset(100, 140)), isFalse);
    expect(hit(const Offset(258, 120)), isTrue);
    expect(hit(const Offset(259, 120)), isFalse,
        reason: 'A touch on the right price ruler is not a drawing touch');
    expect(hit(const Offset(100, 400)), isFalse,
        reason: 'A touch on the bottom time axis is not a drawing touch');
  });

  test('Fibonacci selection follows same clipped line as actual painter', () {
    const plot = Rect.fromLTWH(0, 0, 259, 400);
    bool hit(double fromX, double x) =>
        ChartLineGeometry.hitFibonacciLevels(
          point: Offset(x, 100), fromX: fromX,
          levelYs: const [100], plot: plot);
    expect(hit(-3000, 6), isTrue,
        reason: 'A Fibonacci level from long-ago source bars stays hittable');
    expect(hit(80, 80), isTrue);
    expect(hit(80, 65), isTrue,
        reason: 'A 15px approach to the visible anchor preserves touch target');
    expect(hit(80, 50), isFalse);
    expect(hit(300, 245), isFalse,
        reason: 'An off-right future anchor has no painted segment to hit');
    expect(hit(258, 258), isTrue,
        reason: 'A one-pixel visible segment is still real and selectable');
  });

  test('Fibonacci hit ignores invalid touch and negative tolerance', () {
    const bounds = Rect.fromLTWH(0, 0, 100, 100);
    bool hit(Offset point, {double radius = 17}) =>
        ChartLineGeometry.hitFibonacciLevels(
          point: point, fromX: 0, levelYs: const [25],
          plot: bounds, touchRadius: radius);
    expect(hit(const Offset(double.nan, 25)), isFalse);
    expect(hit(const Offset(double.infinity, 25)), isFalse);
    expect(hit(const Offset(20, double.negativeInfinity)), isFalse);
    expect(hit(const Offset(-1, 25)), isFalse);
    expect(hit(const Offset(20, 25), radius: -1), isFalse);
    expect(hit(const Offset(20, 25), radius: double.nan), isFalse);
    expect(hit(const Offset(20, 25), radius: 0), isTrue);
  });

  test('last-close dashes match the old 6px/2.2px geometry at 320dp', () {
    // 320dp mobile width minus the existing 61dp right price scale.
    const width = 259.0;
    const y = 147.25;
    final metrics = ChartLineGeometry.lastCloseDashPath(
        y: y, plotWidth: width).computeMetrics().toList();
    expect(metrics, hasLength(44));
    for (var index = 0; index < metrics.length; index++) {
      final firstX = index * 6.0;
      final lastX = (firstX + 2.2).clamp(0.0, width);
      final start = metrics[index].getTangentForOffset(0)!.position;
      final end = metrics[index]
          .getTangentForOffset(metrics[index].length)!.position;
      expect(start.dx, closeTo(firstX, 1e-5));
      expect(start.dy, closeTo(y, 1e-5));
      expect(end.dx, closeTo(lastX, 1e-5));
      expect(end.dy, closeTo(y, 1e-5));
      expect(metrics[index].length, closeTo(lastX - firstX, 1e-5));
    }
    expect(metrics.last.length, closeTo(1, 1e-5),
        reason: 'The final short dash must not enter the price ruler');
  });

  test('last-close line batching keeps dash spacing at 390dp and tiny plots',
      () {
    const width = 329.0;
    final metrics = ChartLineGeometry.lastCloseDashPath(
        y: 220, plotWidth: width).computeMetrics().toList();
    expect(metrics, hasLength(55));
    expect(metrics.first.length, closeTo(2.2, 1e-5));
    expect(metrics.last.getTangentForOffset(0)!.position.dx,
        closeTo(324, 1e-5));
    // Flutter PathMetrics stores larger canvas coordinates as float32;
    // near x=324 its 2.2px contour length can differ by ~0.000012px.
    // Keep a subpixel geometry tolerance, not an impossible float64 one.
    expect(metrics.last.length, closeTo(2.2, 1e-4));
    final tiny = ChartLineGeometry.lastCloseDashPath(
        y: 4, plotWidth: 1).computeMetrics().toList();
    expect(tiny, hasLength(1));
    expect(tiny.single.length, closeTo(1, 1e-5));
    for (final invalidWidth in <double>[
      0, -1, double.nan, double.infinity, double.negativeInfinity
    ]) {
      expect(ChartLineGeometry.lastCloseDashPath(
        y: 3, plotWidth: invalidWidth).computeMetrics().isEmpty, isTrue);
    }
    expect(ChartLineGeometry.lastCloseDashPath(
      y: double.nan, plotWidth: width).computeMetrics().isEmpty, isTrue);
    expect(ChartLineGeometry.lastCloseDashPath(
      y: double.infinity, plotWidth: width).computeMetrics().isEmpty, isTrue);
  });

  test('configured 8px/4px horizontal dashes preserve every endpoint', () {
    // The old painter called drawLine 33 times for a 259dp plot.
    const from = Offset(0, 147.25);
    const to = Offset(259, 147.25);
    final contours = ChartLineGeometry.configuredDashPath(
      from: from, to: to).computeMetrics().toList();
    expect(contours, hasLength(33));
    for (var i = 0; i < contours.length; i++) {
      final start = contours[i].getTangentForOffset(0)!.position;
      final end = contours[i]
          .getTangentForOffset(contours[i].length)!.position;
      final firstX = i * 8.0;
      final lastX = (firstX + 4).clamp(0.0, 259.0);
      expect(start.dx, closeTo(firstX, 1e-4));
      expect(start.dy, closeTo(from.dy, 1e-4));
      expect(end.dx, closeTo(lastX, 1e-4));
      expect(end.dy, closeTo(to.dy, 1e-4));
    }
    expect(contours.last.length, closeTo(3, 1e-4),
      reason: 'The final dash must stop at the plot/price-axis boundary');
  });

  test('configured vertical and diagonal strokes keep their direction', () {
    final vertical = ChartLineGeometry.configuredDashPath(
      from: const Offset(24, 2), to: const Offset(24, 100))
        .computeMetrics().toList();
    expect(vertical, hasLength(13));
    expect(vertical.first.getTangentForOffset(0)!.position,
      const Offset(24, 2));
    expect(vertical.last.getTangentForOffset(vertical.last.length)!.position,
      const Offset(24, 100));
    expect(vertical.last.length, closeTo(2, 1e-4));

    // 30-40-50 triangle; includes the final 2px clipped diagonal dash.
    final diagonal = ChartLineGeometry.configuredDashPath(
      from: const Offset(1, 2), to: const Offset(31, 42))
        .computeMetrics().toList();
    expect(diagonal, hasLength(7));
    expect(diagonal.first.length, closeTo(4, 1e-4));
    expect(diagonal.last.length, closeTo(2, 1e-4));
    final end = diagonal.last
        .getTangentForOffset(diagonal.last.length)!.position;
    expect(end.dx, closeTo(31, 1e-4));
    expect(end.dy, closeTo(42, 1e-4));
  });

  test('invalid configured dashes do not emit corrupt path geometry', () {
    for (final point in <Offset>[
      const Offset(double.nan, 0),
      const Offset(double.infinity, 0),
      const Offset(0, double.negativeInfinity),
    ]) {
      expect(ChartLineGeometry.configuredDashPath(
        from: point, to: const Offset(20, 20))
          .computeMetrics().isEmpty, isTrue);
      expect(ChartLineGeometry.configuredDashPath(
        from: const Offset(0, 0), to: point)
          .computeMetrics().isEmpty, isTrue);
    }
    expect(ChartLineGeometry.configuredDashPath(
      from: Offset.zero, to: const Offset(.005, 0))
        .computeMetrics().isEmpty, isTrue);
    expect(ChartLineGeometry.configuredDashPath(
      from: Offset.zero, to: const Offset(1, 0))
        .computeMetrics().single.length, closeTo(1, 1e-4));
  });

  test('trend segment remains between its two anchors', () {
    final lines = ChartLineGeometry.strokes(
      tool: ChartDrawingTool.trendLine,
      start: start, end: end, bounds: bounds,
    );
    expect(lines, hasLength(1));
    expect(lines.single.start, start);
    expect(lines.single.end, end);
  });

  test('ray begins at price/time anchor and extends to plot edge', () {
    final lines = ChartLineGeometry.strokes(
      tool: ChartDrawingTool.ray,
      start: start, end: end, bounds: bounds,
    );
    expect(lines.single.start, start);
    expect(lines.single.end, const Offset(100, 0));
    expect(ChartLineGeometry.distanceToStroke(
        const Offset(80, 20), lines.single), closeTo(0, 1e-8));
  });

  test('extended line clips both past and future screen edges', () {
    final lines = ChartLineGeometry.strokes(
      tool: ChartDrawingTool.extendedLine,
      start: start, end: end, bounds: bounds,
    );
    expect(lines.single.start, const Offset(0, 100));
    expect(lines.single.end, const Offset(100, 0));
  });

  test('horizontal ray uses one candle and grows rightward only', () {
    final lines = ChartLineGeometry.strokes(
      tool: ChartDrawingTool.horizontalRay,
      start: start, end: start, bounds: bounds,
    );
    expect(lines.single.start, start);
    expect(lines.single.end, const Offset(100, 80));
  });

  test('vertical line uses one candle and spans the full price axis', () {
    final lines = ChartLineGeometry.strokes(
      tool: ChartDrawingTool.verticalLine,
      start: start, end: start, bounds: bounds,
    );
    expect(lines.single.start, const Offset(20, 0));
    expect(lines.single.end, const Offset(20, 100));
  });

  test('three-anchor channel creates two independent parallel borders', () {
    final lines = ChartLineGeometry.strokes(
      tool: ChartDrawingTool.parallelChannel,
      start: start, end: end,
      offset: const Offset(45, 30), bounds: bounds,
    );
    expect(lines, hasLength(2));
    expect(lines[0].start, start);
    expect(lines[0].end, end);
    expect(lines[1].start, const Offset(20, 55));
    expect(lines[1].end, const Offset(60, 15));
  });

  test('clipped drawings never extend into the right price scale', () {
    for (final type in ChartDrawingTool.values) {
      if (type == ChartDrawingTool.fibonacci ||
          type == ChartDrawingTool.horizontal) continue;
      final strokes = ChartLineGeometry.strokes(
          tool: type, start: start, end: end,
          offset: const Offset(45, 30), bounds: bounds);
      for (final stroke in strokes) {
        for (final point in [stroke.start, stroke.end]) {
          expect(bounds.inflate(.001).contains(point), isTrue,
              reason: 'Stroke escaped plot bounds: $type $point');
        }
      }
    }
  });

  test('early line culling skips only shapes proven entirely outside plot',
      () {
    const width = 259.0; // 320dp phone minus 61dp price ruler
    for (final tool in <ChartDrawingTool>[
      ChartDrawingTool.trendLine,
      ChartDrawingTool.horizontal,
    ]) {
      expect(ChartLineGeometry.definitelyOffscreenHorizontally(
        tool: tool, startX: -80, endX: -1, plotWidth: width), isTrue);
      expect(ChartLineGeometry.definitelyOffscreenHorizontally(
        tool: tool, startX: 260, endX: 400, plotWidth: width), isTrue);
      expect(ChartLineGeometry.definitelyOffscreenHorizontally(
        tool: tool, startX: -80, endX: 400, plotWidth: width), isFalse,
        reason: 'The finite segment may cross the on-screen candles');
      expect(ChartLineGeometry.definitelyOffscreenHorizontally(
        tool: tool, startX: 0, endX: -400, plotWidth: width), isFalse,
        reason: 'A real endpoint on the plot border is not offscreen');
    }
    expect(ChartLineGeometry.definitelyOffscreenHorizontally(
      tool: ChartDrawingTool.verticalLine,
      startX: -1, endX: -1, plotWidth: width), isTrue);
    expect(ChartLineGeometry.definitelyOffscreenHorizontally(
      tool: ChartDrawingTool.verticalLine,
      startX: width, endX: width, plotWidth: width), isFalse);
    expect(ChartLineGeometry.definitelyOffscreenHorizontally(
      tool: ChartDrawingTool.horizontalRay,
      startX: width + 1, endX: -900, plotWidth: width), isTrue);
    expect(ChartLineGeometry.definitelyOffscreenHorizontally(
      tool: ChartDrawingTool.horizontalRay,
      startX: -900, endX: -900, plotWidth: width), isFalse);
  });

  test('reversed Fibonacci and infinite rays keep lines entering the plot',
      () {
    const width = 329.0; // 390dp Android phone
    bool culled(ChartDrawingTool tool, double x1, double x2) =>
        ChartLineGeometry.definitelyOffscreenHorizontally(
          tool: tool, startX: x1, endX: x2, plotWidth: width);
    // The painter extends Fibonacci levels from min(x1,x2), NOT x1 alone.
    expect(culled(ChartDrawingTool.fibonacci, 500, -2000), isFalse);
    expect(culled(ChartDrawingTool.fibonacci, 500, 350), isTrue);
    expect(culled(ChartDrawingTool.fibonacci, -2000, 350), isFalse);
    expect(ChartLineGeometry.fibonacciLevelStroke(
      fromX: -2000, levelY: 50,
      plot: const Rect.fromLTWH(0, 0, 329, 200)), isNotNull);
    // Extended/ray/channel drawings can enter the viewport even if the
    // source anchors appear completely outside on one side.
    for (final tool in <ChartDrawingTool>[
      ChartDrawingTool.ray,
      ChartDrawingTool.extendedLine,
      ChartDrawingTool.parallelChannel,
    ]) {
      expect(culled(tool, -500, -100), isFalse);
      expect(culled(tool, 500, 900), isFalse);
    }
    expect(culled(ChartDrawingTool.trendLine, double.nan, 400), isFalse);
    expect(culled(ChartDrawingTool.trendLine, 400, 500), isTrue);
    expect(ChartLineGeometry.definitelyOffscreenHorizontally(
      tool: ChartDrawingTool.trendLine, startX: 10, endX: 20,
      plotWidth: double.infinity), isFalse);
  });

  test('30k real indexed source anchors are conservatively culled at deep '
      '3px and 60px zoom', () {
    var definitelyInvisible = 0;
    var kept = 0;
    for (final plotWidth in <double>[259, 329]) {
      for (final width in <double>[3, 10, 60]) {
        for (final scroll in <double>[0, 40, 1400]) {
          final viewport = ChartViewport(
              barWidth: width, scrollBars: scroll, rightMarginBars: 4);
          for (var index = 0; index < 1800; index++) {
            final x1 = viewport.chartX(index: index,
                candleCount: 1801, plotWidth: plotWidth);
            final x2 = viewport.chartX(index: index + 1,
                candleCount: 1801, plotWidth: plotWidth);
            final isCulled = ChartLineGeometry.definitelyOffscreenHorizontally(
                tool: ChartDrawingTool.trendLine,
                startX: x1, endX: x2, plotWidth: plotWidth);
            if (isCulled) {
              definitelyInvisible++;
              expect(ChartLineGeometry.strokes(
                tool: ChartDrawingTool.trendLine,
                start: Offset(x1, 50), end: Offset(x2, 100),
                bounds: Rect.fromLTWH(0, 0, plotWidth, 180)), isEmpty,
                reason: 'A pruned segment must NEVER contain a visible '
                    'real-source stroke');
            } else {
              kept++;
            }
          }
        }
      }
    }
    expect(definitelyInvisible, greaterThan(28000));
    expect(kept, greaterThan(0));
  });
}
