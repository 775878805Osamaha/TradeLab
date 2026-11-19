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
}
