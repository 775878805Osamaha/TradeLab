import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  test('a left drag creates right-side whitespace and centers the last bar', () {
    const initial = ChartViewport();
    final next = initial.pan(deltaX: -150, plotWidth: 300, candleCount: 90);
    expect(next.scrollBars, -15);
    final x = next.chartX(index: 89, candleCount: 90, plotWidth: 300);
    expect(x, closeTo(145, .01));
    expect(next.futurePaddingBars, 15);
  });

  test('a right drag removes whitespace then visits older bars', () {
    const initial = ChartViewport(scrollBars: -12);
    final latest = initial.pan(deltaX: 120, plotWidth: 300, candleCount: 90);
    expect(latest.scrollBars, closeTo(0, .001));
    final older = latest.pan(deltaX: 45, plotWidth: 300, candleCount: 90);
    expect(older.scrollBars, closeTo(4.5, .001));
  });

  test('pinch keeps the same price bar under the anchor point', () {
    const initial = ChartViewport(scrollBars: 3);
    final index = 75;
    final oldX = initial.chartX(index: index, candleCount: 90, plotWidth: 300);
    final after = initial.pinch(
      scale: 2,
      initialFocalX: oldX,
      currentFocalX: oldX,
      plotWidth: 300,
      candleCount: 90,
    );
    expect(after.barWidth, 20);
    final newX = after.chartX(index: index, candleCount: 90, plotWidth: 300);
    expect(newX, closeTo(oldX, .001));
  });

  test('scrolling and zooming stay within documented bounds', () {
    const initial = ChartViewport();
    final maxFuture = initial.pan(
      deltaX: -100000, plotWidth: 300, candleCount: 90);
    expect(maxFuture.scrollBars, closeTo(-20.4, .001));
    final maxHistory = initial.pan(
      deltaX: 100000, plotWidth: 300, candleCount: 90);
    expect(maxHistory.scrollBars, 89);
    final zoomed = initial.pinch(
      scale: 100, initialFocalX: 150, currentFocalX: 150,
      plotWidth: 300, candleCount: 90);
    expect(zoomed.barWidth, 30);
  });

  test('visible subset never exceeds the known past candles', () {
    const viewport = ChartViewport(scrollBars: 11);
    final (start, end) = viewport.visibleIndices(
      plotWidth: 300, candleCount: 50);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, lessThanOrEqualTo(50));
    expect(start, lessThan(end));
  });
}
