import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  for (final plotWidth in <double>[260, 320, 390]) {
    test('Replay date/oldest/random selection reveals real candle at ${plotWidth}dp',
        () {
      const original = ChartViewport(
        barWidth: 12, scrollBars: 0, rightMarginBars: 1.5);
      const count = 500;
      for (final index in <int>[0, 1, 17, 250, 498]) {
        final focused = original.revealHistoricalBar(
          index: index, candleCount: count, plotWidth: plotWidth);
        final x = focused.chartX(
          index: index, candleCount: count, plotWidth: plotWidth);
        expect(x, greaterThanOrEqualTo(0),
            reason: 'Date-picked historical bar must not remain offscreen');
        expect(x, lessThanOrEqualTo(plotWidth));
        expect(focused.indexAt(
          x: x, plotWidth: plotWidth, candleCount: count), index,
            reason: 'The blue line must stay anchored to its original bar');
        expect(focused.barWidth, original.barWidth,
            reason: 'Navigating to a date must not reset chart zoom');
        expect(focused.rightMarginBars, original.rightMarginBars);
      }
    });
  }

  test('Invalid history never causes a synthetic Replay selection', () {
    const current = ChartViewport(barWidth: 16, scrollBars: 7);
    expect(current.revealHistoricalBar(
      index: -1, candleCount: 20, plotWidth: 320), current);
    expect(current.revealHistoricalBar(
      index: 20, candleCount: 20, plotWidth: 320), current);
    expect(current.revealHistoricalBar(
      index: 0, candleCount: 0, plotWidth: 320), current);
    expect(current.revealHistoricalBar(
      index: 0, candleCount: 20, plotWidth: double.nan), current);
  });
}
