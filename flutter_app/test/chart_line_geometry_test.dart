import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_annotations.dart';
import 'package:tradelab_flutter/chart/chart_line_geometry.dart';

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
}
