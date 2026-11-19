import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_price_rectangle.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  test('rectangle timestamp follows actual chart New York vs UTC display', () {
    final winter = DateTime.utc(2026, 11, 19, 2, 30)
        .millisecondsSinceEpoch;
    final summer = DateTime.utc(2026, 7, 15, 2, 30)
        .millisecondsSinceEpoch;
    expect(ChartRectangleTimeLabel.fromSource(winter, ChartTimeZone.utc),
        '19/11 02:30 UTC');
    expect(ChartRectangleTimeLabel.fromSource(
        winter, ChartTimeZone.newYork), '18/11 21:30 NY UTC-5');
    expect(ChartRectangleTimeLabel.fromSource(
        summer, ChartTimeZone.newYork), '14/07 22:30 NY UTC-4',
        reason: 'Historical source UTC time uses the correct summer DST');
    final local = ChartTimeZone.device.displayDate(winter);
    String two(int n) => n.toString().padLeft(2, '0');
    expect(ChartRectangleTimeLabel.fromSource(
        winter, ChartTimeZone.device),
        '${two(local.day)}/${two(local.month)} '
        '${two(local.hour)}:${two(local.minute)} LOCAL');
    // Presentation never alters the actual market-data timestamp.
    expect(ChartTimeZone.utc.displayDate(winter).millisecondsSinceEpoch,
        winter);
  });

  test('999 rectangles above price range never require clipped paint passes',
      () {
    const viewport = ChartViewport(barWidth: 3);
    const scale = ChartPriceScale(100, 120, 200);
    const plotWidth = 259.0;
    final drawings = <ChartPriceRectangle>[
      ...List.generate(999, (i) => ChartPriceRectangle(
          startIndex: 940, endIndex: 980,
          upper: 145 + i.toDouble(), lower: 130 + i.toDouble())),
      const ChartPriceRectangle(
          startIndex: 940, endIndex: 980, upper: 115, lower: 105),
    ];
    var visible = 0;
    for (var i = 0; i < drawings.length; i++) {
      final bounds = PriceRectangleGeometry.rect(
          drawings[i], viewport, scale, 1000, plotWidth);
      if (PriceRectangleGeometry.visibleInPlot(
          bounds, plotWidth, scale.height,
          selected: i == drawings.length - 1)) {
        visible++;
      }
    }
    expect(visible, 1,
        reason: 'Only the on-screen rectangle may allocate fill/border '
            'paint operations in a 1000-annotation historical chart');
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, -20, 80, -5), 259, 200), false);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, -20, 80, -5), 259, 200,
        selected: true), true,
        reason: 'Visible 11.5px edge of a selected handle stays drawable');
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, -30, 80, -12), 259, 200,
        selected: true), false);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, 205, 80, 220), 259, 200,
        selected: true), true);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, 212, 80, 230), 259, 200,
        selected: true), false);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(double.nan, 10, 80, 100), 259, 200), false);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, 10, 80, 100), 0, 200), false);
  });

  test('horizontal/offscreen and Replay hidden ranges retain existing guards',
      () {
    const viewport = ChartViewport(barWidth: 3);
    const scale = ChartPriceScale(100, 120, 200);
    const drawing = ChartPriceRectangle(
        startIndex: 998, endIndex: 1000, upper: 115, lower: 105);
    expect(drawing.visibleAt(1000), false,
        reason: 'A Replay future drawing cannot become visible');
    expect(drawing.visibleAt(1001), true);
    final area = PriceRectangleGeometry.rect(
        drawing, viewport, scale, 1001, 259);
    expect(PriceRectangleGeometry.visibleInPlot(
        area, 259, 200), true,
        reason: 'A real visible rectangle must not disappear at 3px candles');
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(-200, 12, -1, 100), 259, 200), false);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(260, 12, 340, 100), 259, 200), false);
  });

  test('horizontal early culling matches old rectangle bounds at every '
      '3px/60px mobile zoom and scroll position', () {
    const scale = ChartPriceScale(100, 120, 200);
    // Large historical drawing archives must keep exactly the same visible
    // rectangles as the old full-price geometry without drawing offscreen.
    final drawings = List<ChartPriceRectangle>.generate(2000, (i) =>
        ChartPriceRectangle(startIndex: i, endIndex: i + 1,
            upper: 115, lower: 105));
    var definitelyOffscreen = 0;
    var visible = 0;
    for (final plotWidth in <double>[259, 329]) {
      for (final barWidth in <double>[3, 10, 60]) {
        for (final scroll in <double>[-15, 0, 35, 480, 1500]) {
          final viewport = ChartViewport(
            barWidth: barWidth,
            scrollBars: scroll,
            rightMarginBars: 4,
          );
          for (final drawing in drawings) {
            final oldBounds = PriceRectangleGeometry.rect(
                drawing, viewport, scale, 2001, plotWidth);
            final oldVisible = PriceRectangleGeometry.visibleInPlot(
                oldBounds, plotWidth, scale.height);
            final span = PriceRectangleGeometry.visibleHorizontalSpan(
                drawing, viewport, 2001, plotWidth);
            expect(span != null, oldVisible,
                reason: 'Viewport $plotWidth / ${barWidth}px, '
                    'scroll $scroll, index ${drawing.startIndex}');
            if (span == null) {
              definitelyOffscreen++;
            } else {
              visible++;
              expect(span.left, oldBounds.left);
              expect(span.right, oldBounds.right);
            }
          }
        }
      }
    }
    expect(definitelyOffscreen, greaterThan(45000),
        reason: 'Most of 60k historical rectangle checks should skip '
            'price transforms, clipping, and drawing allocations');
    expect(visible, greaterThan(0));
  });

  test('partly clipped historical handles still paint and receive touches',
      () {
    const plotWidth = 259.0;
    const scale = ChartPriceScale(100, 120, 200);
    const viewport = ChartViewport(barWidth: 3, rightMarginBars: 0);
    const candleCount = 1000;
    final (from, to) = viewport.visibleIndices(
        plotWidth: plotWidth, candleCount: candleCount);
    expect(to, greaterThan(from + 4));
    final partiallyVisible = ChartPriceRectangle(
      startIndex: from - 2, endIndex: from + 5,
      upper: 115, lower: 105,
    );
    final bounds = PriceRectangleGeometry.rect(
        partiallyVisible, viewport, scale, candleCount, plotWidth);
    expect(bounds.right, greaterThan(0));
    expect(PriceRectangleGeometry.visibleHorizontalSpan(
        partiallyVisible, viewport, candleCount, plotWidth), isNotNull);
    final hit = PriceRectangleGeometry.hitTest(
        Offset(bounds.center.dx.clamp(0.0, plotWidth - 1),
            bounds.center.dy),
        [partiallyVisible], viewport, scale, candleCount, plotWidth);
    expect(hit?.$1, 0,
        reason: 'Selected partly visible rect must retain its hit target');
    final whollyOld = ChartPriceRectangle(
        startIndex: 0, endIndex: 1, upper: 115, lower: 105);
    expect(PriceRectangleGeometry.visibleHorizontalSpan(
        whollyOld, viewport, candleCount, plotWidth), isNull);
    expect(PriceRectangleGeometry.hitTest(
        const Offset(4, 100), [whollyOld], viewport, scale,
        candleCount, plotWidth), isNull);
  });

  test('Replay and malformed viewports never expose future rectangles',
      () {
    const source = ChartPriceRectangle(
        startIndex: 30, endIndex: 40, upper: 210, lower: 190);
    const viewport = ChartViewport(barWidth: 10);
    expect(PriceRectangleGeometry.visibleHorizontalSpan(
        source, viewport, 40, 259), isNull,
        reason: 'End candle belongs to the unrevealed Replay future');
    expect(PriceRectangleGeometry.visibleHorizontalSpan(
        source, viewport, 41, 259), isNotNull);
    for (final invalid in <double>[
      double.nan, double.infinity, double.negativeInfinity, 0, -1
    ]) {
      expect(PriceRectangleGeometry.visibleHorizontalSpan(
          source, viewport, 41, invalid), isNull);
    }
    expect(PriceRectangleGeometry.visibleHorizontalSpan(
        source, const ChartViewport(barWidth: double.nan),
        41, 259), isNull);
    expect(PriceRectangleGeometry.visibleHorizontalSpan(
        source, const ChartViewport(scrollBars: double.infinity),
        41, 259), isNull);
  });
}
