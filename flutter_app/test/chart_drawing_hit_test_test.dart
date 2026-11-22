import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_annotations.dart';
import 'package:tradelab_flutter/chart/chart_drawing_hit_test.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  const visibleCount = 120000;
  const viewport = ChartViewport(barWidth: 10);
  double sourceX(int index, double width) => viewport.chartX(
      index: index, candleCount: visibleCount, plotWidth: width);

  int? hit(Offset point, List<ChartPattern> patterns, {
    double plotWidth = 259,
    double plotHeight = 400,
    int revealed = visibleCount,
    int? selected,
    double Function(double)? sourceY,
    double Function(int)? sourceXOverride,
  }) => ChartDrawingHitTest.hit(
    position: point, patterns: patterns, revealedCount: revealed,
    plotWidth: plotWidth, plotHeight: plotHeight,
    selectedPatternIndex: selected,
    sourceX: sourceXOverride ?? (i) => sourceX(i, plotWidth),
    sourceY: sourceY ?? (price) => price,
  );

  test('120k bars with 6000 old finite drawings skip offscreen price work',
      () {
    // An actual chart geometry regression: old _hitPattern evaluated the
    // screen price of 12,000 invisible anchors at every touch-down.
    final drawings = <ChartPattern>[
      const ChartPattern(
        tool: ChartDrawingTool.trendLine,
        start: ChartAnchor(119985, 200),
        end: ChartAnchor(119990, 200)),
      for (var i = 0; i < 6000; i++)
        ChartPattern(
          tool: ChartDrawingTool.trendLine,
          start: ChartAnchor(i * 2, 100),
          end: ChartAnchor(i * 2 + 1, 101)),
    ];
    for (final width in <double>[259, 329]) {
      var priceTransformCalls = 0;
      var sourceXCalls = 0;
      final middleX = sourceX(119987, width);
      final selected = hit(Offset(middleX, 200), drawings,
        plotWidth: width,
        sourceY: (price) {
          priceTransformCalls++;
          return price;
        },
        sourceXOverride: (index) {
          sourceXCalls++;
          return sourceX(index, width);
        });
      expect(selected, 0,
          reason: 'The older finite drawings must not steal a chart touch');
      expect(priceTransformCalls, 2,
          reason: 'Only two actually visible source prices need scaling');
      expect(sourceXCalls, 12002,
          reason: 'Source x culling remains constant-time per drawing');
      expect(drawings.first.start.index, 119985);
    }
  });

  test('unbounded rays and crosslines remain hittable from historical anchors',
      () {
    final drawings = <ChartPattern>[
      const ChartPattern(
        tool: ChartDrawingTool.ray,
        start: ChartAnchor(100, 200),
        end: ChartAnchor(101, 200)),
      const ChartPattern(
        tool: ChartDrawingTool.crossLine,
        start: ChartAnchor(110, 150),
        end: ChartAnchor(110, 150)),
    ];
    expect(hit(const Offset(100, 150), drawings), 1,
        reason: 'Crossline arm still reaches the current plotted candle area');
    expect(hit(const Offset(100, 200), drawings), 0,
        reason: 'The ray is infinite to the right, unlike a finite line');
  });

  test('Fibonacci levels from offscreen historical bars remain selectable',
      () {
    const pattern = ChartPattern(
      tool: ChartDrawingTool.fibonacci,
      start: ChartAnchor(50, 100),
      end: ChartAnchor(60, 200));
    expect(hit(const Offset(100, 150), [pattern]), 0,
        reason: 'Real 50% level remains visible even with ancient anchors');
    expect(hit(const Offset(100, 173), [pattern]), isNull);
    expect(hit(const Offset(259, 150), [pattern]), isNull,
        reason: 'Price ruler cannot select a drawing');
  });

  test('Replay future and negative source indices are never transformed',
      () {
    const visible = ChartPattern(
      tool: ChartDrawingTool.infoLine,
      start: ChartAnchor(10, 100),
      end: ChartAnchor(15, 100));
    const future = ChartPattern(
      tool: ChartDrawingTool.infoLine,
      start: ChartAnchor(20, 100),
      end: ChartAnchor(40, 100));
    const negative = ChartPattern(
      tool: ChartDrawingTool.trendLine,
      start: ChartAnchor(-1, 100),
      end: ChartAnchor(12, 100));
    var xReads = 0, yReads = 0;
    int? check(int revealed) => hit(
      const Offset(100, 100), const [visible, future, negative],
      revealed: revealed,
      sourceXOverride: (i) {
        xReads++;
        return 100;
      },
      sourceY: (price) {
        yReads++;
        return price;
      },
    );
    expect(check(16), 0);
    expect(xReads, 2, reason: 'Only revealed two-anchor drawing is inspected');
    expect(yReads, 2);
    xReads = 0; yReads = 0;
    expect(check(0), isNull);
    expect(xReads, 0);
    expect(yReads, 0);
  });

  test('overlapping drawings keep reverse painter order and channel handles',
      () {
    const lower = ChartPattern(
      tool: ChartDrawingTool.trendLine,
      start: ChartAnchor(119985, 200),
      end: ChartAnchor(119990, 200));
    const upper = ChartPattern(
      tool: ChartDrawingTool.parallelChannel,
      start: ChartAnchor(119985, 200),
      end: ChartAnchor(119990, 200),
      offsetAnchor: ChartAnchor(119987, 220));
    final touchX = sourceX(119987, 259);
    expect(hit(Offset(touchX, 200), const [lower, upper]), 1,
        reason: 'The most recent drawing retains first touch priority');
    expect(hit(Offset(touchX, 220), const [lower, upper]), 1,
        reason: 'Parallel-channel second stroke remains active');
  });

  test('invalid touches require zero drawing evaluation', () {
    const drawing = ChartPattern(
      tool: ChartDrawingTool.trendLine,
      start: ChartAnchor(119985, 200),
      end: ChartAnchor(119990, 200));
    var reads = 0;
    int? attempt(Offset point, {double width = 259}) => hit(
      point, const [drawing], plotWidth: width,
      sourceXOverride: (i) {
        reads++;
        return sourceX(i, 259);
      });
    expect(attempt(const Offset(double.nan, 100)), isNull);
    expect(attempt(const Offset(double.infinity, 100)), isNull);
    expect(attempt(const Offset(259, 100)), isNull);
    expect(attempt(const Offset(100, 400)), isNull);
    expect(attempt(const Offset(100, 200), width: 0), isNull);
    expect(reads, 0);
  });
}
