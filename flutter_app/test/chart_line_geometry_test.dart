import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_annotations.dart';
import 'package:tradelab_flutter/chart/chart_line_geometry.dart';

void main() {
  const bounds = Rect.fromLTWH(0, 0, 100, 100);
  const start = Offset(20, 80);
  const end = Offset(60, 40);

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
