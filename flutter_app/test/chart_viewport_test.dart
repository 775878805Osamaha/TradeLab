import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

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

  test('historical Range regrouping keeps the same BID bar at the same x', () {
    const before = ChartViewport(barWidth: 12, scrollBars: 28.75);
    const plotWidth = 360.0;
    const oldCount = 120;
    const oldAnchor = 90;
    const newCount = 175;
    const newAnchor = 141;
    final oldX = before.chartX(
        index: oldAnchor, candleCount: oldCount, plotWidth: plotWidth);
    final restored = before.remapHistoricalAnchor(
      oldCount: oldCount, oldIndex: oldAnchor,
      newCount: newCount, newIndex: newAnchor,
    );
    expect(restored.barWidth, before.barWidth);
    expect(restored.chartX(
        index: newAnchor, candleCount: newCount, plotWidth: plotWidth),
        closeTo(oldX, .000001));
  });

  test('historical anchor remap does not disturb future whitespace', () {
    const preview = ChartViewport(barWidth: 10, scrollBars: -8);
    final restored = preview.remapHistoricalAnchor(
      oldCount: 40, oldIndex: 30,
      newCount: 120, newIndex: 110,
    );
    expect(restored, preview);
  });

  test('closed candles keep the same historical bar at the same x', () {
    const viewport = ChartViewport(barWidth: 12, scrollBars: 18.5);
    final originalX = viewport.chartX(
        index: 75, candleCount: 100, plotWidth: 360);
    final appended = viewport.afterAppending(3);
    expect(appended.barWidth, 12);
    expect(appended.chartX(index: 75, candleCount: 103, plotWidth: 360),
        closeTo(originalX, .000001));
  });

  test('closed candles preserve intentional right-side chart whitespace', () {
    const viewport = ChartViewport(barWidth: 10, scrollBars: -9);
    final originalX = viewport.chartX(
        index: 99, candleCount: 100, plotWidth: 300);
    final appended = viewport.afterAppending(2);
    expect(appended.scrollBars, -7);
    expect(appended.chartX(index: 99, candleCount: 102, plotWidth: 300),
        closeTo(originalX, .000001));
  });

  test('closed candles follow latest only at the live edge', () {
    const viewport = ChartViewport(barWidth: 10);
    expect(identical(viewport.afterAppending(2), viewport), isTrue);
    expect(identical(viewport.afterAppending(0), viewport), isTrue);
  });

  test('visible subset never exceeds the known past candles', () {
    const viewport = ChartViewport(scrollBars: 11);
    final (start, end) = viewport.visibleIndices(
      plotWidth: 300, candleCount: 50);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, lessThanOrEqualTo(50));
    expect(start, lessThan(end));
  });

  test('a drawing stays on its market price when the viewport zooms', () {
    final candles = List<TradeCandle>.generate(100, (i) =>
        TradeCandle(100.0 + i, 101.0 + i, 99.0 + i, 100.5 + i));
    const viewport = ChartViewport();
    final scale = ChartPriceScale.visible(candles, viewport, 300, 400);
    const savedLevelPrice = 188.25;
    expect(scale.price(scale.y(savedLevelPrice)), closeTo(savedLevelPrice, 1e-9));
    final zoomed = viewport.pinch(scale: 2, initialFocalX: 150,
        currentFocalX: 150, plotWidth: 300, candleCount: 100);
    final scaleAfterZoom = ChartPriceScale.visible(candles, zoomed, 300, 400);
    expect(scaleAfterZoom.price(scaleAfterZoom.y(savedLevelPrice)),
        closeTo(savedLevelPrice, 1e-9));
  });

  test('touch coordinates resolve actual candles, not future whitespace', () {
    const viewport = ChartViewport(scrollBars: -15);
    final x = viewport.chartX(index: 89, candleCount: 90, plotWidth: 300);
    expect(viewport.indexAt(x: x, plotWidth: 300, candleCount: 90), 89);
    expect(viewport.indexAt(x: 290, plotWidth: 300, candleCount: 90),
        isNull);
    expect(viewport.indexAt(x: -1, plotWidth: 300, candleCount: 90),
        isNull);
  });

  test('second finger rebases pinch after an existing one-finger pan', () {
    final gesture = ChartTouchGesture();
    const width = 300.0;
    const candles = 100;
    ChartViewport update(ChartViewport viewport,
        {required int pointers, required double focal,
        required double scale, required double dx}) =>
      gesture.update(
        viewport: viewport, pointerCount: pointers, focalX: focal,
        scale: scale, deltaX: dx, plotWidth: width, candleCount: candles);

    const original = ChartViewport();
    final panned = update(original,
        pointers: 1, focal: 150, scale: 1, dx: 80);
    expect(panned.scrollBars, 8);
    const selected = 80;
    final xBefore = panned.chartX(
        index: selected, candleCount: candles, plotWidth: width);
    final secondFinger = update(panned,
        pointers: 2, focal: xBefore, scale: 1.2, dx: -40);
    expect(secondFinger, panned,
        reason: 'touching with a second finger must not jump the chart');
    expect(gesture.ignoredPointerTransition, isTrue);
    final zoomed = update(secondFinger,
        pointers: 2, focal: xBefore + 20, scale: 2.4, dx: 20);
    expect(zoomed.barWidth, 20);
    expect(zoomed.chartX(
        index: selected, candleCount: candles, plotWidth: width),
        closeTo(xBefore + 20, .000001));
    expect(gesture.hadMultiTouch, isTrue);

    final lifted = update(zoomed,
        pointers: 1, focal: 25, scale: 2.4, dx: -180);
    expect(lifted, zoomed,
        reason: 'centroid shift on finger lift must not move chart');
    expect(gesture.ignoredPointerTransition, isTrue);
    final resumed = update(lifted,
        pointers: 1, focal: 20, scale: 2.4, dx: -30);
    expect(resumed.scrollBars, lessThan(lifted.scrollBars));
  });

  test('tiny one-finger jitter is not a valid inertial chart fling', () {
    final gesture = ChartTouchGesture();
    var viewport = const ChartViewport();
    viewport = gesture.update(
      viewport: viewport, pointerCount: 1, focalX: 151,
      scale: 1, deltaX: 1, plotWidth: 300, candleCount: 50);
    expect(viewport.scrollBars, closeTo(.1, .0001));
    expect(gesture.horizontalTravel, 1);
    expect(chartShouldFling(
      horizontalVelocity: 4000, horizontalTravel: gesture.horizontalTravel,
      candleCount: 50, multiTouch: gesture.hadMultiTouch,
      editingDrawing: false, reducedMotion: false), isFalse);
  });

  test('momentum is limited to deliberate one-finger chart pans', () {
    bool eligible(double speed, {int count = 100, bool pinch = false,
        bool draw = false, bool reduce = false,
        double travel = 100}) => chartShouldFling(
          horizontalVelocity: speed,
          horizontalTravel: travel,
          candleCount: count,
          multiTouch: pinch,
          editingDrawing: draw,
          reducedMotion: reduce,
        );
    expect(eligible(1200), isTrue);
    expect(eligible(-1200), isTrue);
    expect(eligible(150), isFalse);
    expect(eligible(1500, travel: 4), isFalse);
    expect(eligible(1500, travel: 14), isTrue);
    expect(eligible(1500, travel: double.nan), isFalse);
    expect(eligible(double.nan), isFalse);
    expect(eligible(double.infinity), isFalse);
    expect(eligible(800, count: 1), isFalse);
    expect(eligible(800, pinch: true), isFalse);
    expect(eligible(800, draw: true), isFalse);
    expect(eligible(800, reduce: true), isFalse);
  });

  test('momentum displacement preserves direction and viewport bounds', () {
    const viewport = ChartViewport(barWidth: 10, scrollBars: 30);
    final right = viewport.pan(deltaX: 42, plotWidth: 300, candleCount: 200);
    final left = viewport.pan(deltaX: -42, plotWidth: 300, candleCount: 200);
    expect(right.scrollBars, greaterThan(viewport.scrollBars));
    expect(left.scrollBars, lessThan(viewport.scrollBars));
    final nearEnd = const ChartViewport(scrollBars: 199).pan(
        deltaX: 5000, plotWidth: 300, candleCount: 200);
    expect(nearEnd.scrollBars, lessThanOrEqualTo(199));
  });
}
