import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('crosshair forex sub-pip price agrees with its painted horizontal line',
      () {
    // Manual price-axis zoom can expose a range UNDER 0.00001.
    // The old crosshair label incorrectly enforced a separate 0.00001 span,
    // so the price printed at y=height was not the price drawn there.
    const scale = ChartPriceScale(1.072101, 1.072105, 420);
    expect(scale.maximum - scale.minimum, lessThan(.00001));
    for (final y in <double>[0, 23.5, 105, 210, 370.2, 420]) {
      final displayed = scale.crosshairPrice(y);
      expect(displayed, isNotNull);
      expect(displayed, closeTo(scale.price(y), 1e-12),
          reason: 'The crosshair tag must use the exact candle price scale');
      expect(scale.y(displayed!), closeTo(y, 1e-7),
          reason: 'The label must identify its painted horizontal price');
    }
    expect(scale.crosshairPrice(420), closeTo(1.072101, 1e-12));
    expect(scale.crosshairPrice(0), closeTo(1.072105, 1e-12));
    // A reconstructed, wider proxy span would be demonstrably wrong.
    final incorrectPrice = scale.maximum - .00001;
    expect((incorrectPrice - scale.crosshairPrice(420)!).abs(),
        greaterThan(.000005));
  });

  test('fine EURUSD chart crosshair preserves price after ruler pinch and resize',
      () {
    const original = ChartPriceScale(1.082000, 1.082006, 320);
    final zoomed = original.dragPriceAxis(deltaY: -120, focalY: 190)
        .dragPriceAxis(deltaY: -120, focalY: 190);
    expect(zoomed.maximum - zoomed.minimum, lessThan(.000006));
    final anchor = original.price(190);
    expect(zoomed.crosshairPrice(190), closeTo(anchor, 1e-12),
        reason: 'Manual zoom must not move the finger-anchored market price');
    final taller = zoomed.withHeight(640);
    expect(taller.crosshairPrice(380), closeTo(anchor, 1e-12),
        reason: 'Switching focus/chart height must preserve price axes');
    expect(taller.y(taller.crosshairPrice(380)!), closeTo(380, 1e-6));
    expect(zoomed.crosshairPrice(-20),
        closeTo(zoomed.maximum, 1e-12));
    expect(zoomed.crosshairPrice(999),
        closeTo(zoomed.minimum, 1e-12));
  });

  test('crosshair refuses nonfinite or unusable price ruler coordinates',
      () {
    const valid = ChartPriceScale(3987, 3988, 320);
    expect(valid.crosshairPrice(double.nan), isNull);
    expect(valid.crosshairPrice(double.infinity), isNull);
    expect(valid.crosshairPrice(double.negativeInfinity), isNull);
    expect(const ChartPriceScale(1, 1, 320).crosshairPrice(100), isNull);
    expect(const ChartPriceScale(1, 2, 0).crosshairPrice(100), isNull);
    expect(const ChartPriceScale(1, 2, double.nan)
        .crosshairPrice(100), isNull);
    expect(const ChartPriceScale(double.nan, 2, 320)
        .crosshairPrice(100), isNull);
  });

  test('right-price-axis drag zooms prices around touch without time pan', () {
    const scale = ChartPriceScale(100, 200, 400);
    const viewport = ChartViewport(barWidth: 12, scrollBars: 21);
    const anchorY = 120.0;
    final anchorPrice = scale.price(anchorY);
    final candleX = viewport.chartX(
        index: 45, candleCount: 100, plotWidth: 360);
    final zoomed = scale.dragPriceAxis(deltaY: -60, focalY: anchorY);
    expect(zoomed.maximum - zoomed.minimum,
        lessThan(scale.maximum - scale.minimum),
        reason: 'Dragging the right price ruler up zooms into prices');
    expect(zoomed.price(anchorY), closeTo(anchorPrice, 1e-9),
        reason: 'The market price touched by the finger remains anchored');
    expect(zoomed.y(anchorPrice), closeTo(anchorY, 1e-8));
    expect(viewport.chartX(index: 45, candleCount: 100, plotWidth: 360),
        candleX,
        reason: 'Vertical price-axis zoom never changes candle timestamps');
    final zoomedOut = zoomed.dragPriceAxis(deltaY: 60, focalY: anchorY);
    expect(zoomedOut.maximum - zoomedOut.minimum,
        closeTo(scale.maximum - scale.minimum, 1e-8));
    expect(zoomedOut.price(anchorY), closeTo(anchorPrice, 1e-8));
  });

  test('manual price range retains market anchors across chart height', () {
    const original = ChartPriceScale(1900, 1950, 300);
    final expanded = original.withHeight(600);
    expect(expanded.minimum, original.minimum);
    expect(expanded.maximum, original.maximum);
    expect(expanded.price(360), closeTo(original.price(180), 1e-9));
    expect(expanded.y(1925), closeTo(300, 1e-9));
    expect(original.y(1925), closeTo(150, 1e-9));
  });

  test('invalid axis gestures cannot corrupt price scale or broker history',
      () {
    const original = ChartPriceScale(1.071, 1.077, 400);
    expect(identical(original.dragPriceAxis(
        deltaY: double.nan, focalY: 100), original), isTrue);
    expect(identical(original.dragPriceAxis(
        deltaY: 70, focalY: double.infinity), original), isTrue);
    expect(identical(original.dragPriceAxis(
        deltaY: 0, focalY: 100), original), isTrue);
    const flat = ChartPriceScale(10, 10, 400);
    expect(identical(flat.dragPriceAxis(
        deltaY: 70, focalY: 100), flat), isTrue,
        reason: 'Unusable zero-span scales cannot be changed by dragging');
  });

  test('crosshair guide and time marker agree at 3px source candles', () {
    const viewport = ChartViewport(
        barWidth: ChartViewport.minBarWidth,
        scrollBars: 3, rightMarginBars: 4);
    const count = 200;
    const index = 180;
    const width = 320.0;
    final trueX = viewport.chartX(
        index: index, candleCount: count, plotWidth: width);
    final guide = ChartCrosshairSnap.resolve(
      viewport: viewport,
      touchX: trueX + 1.2,
      plotWidth: width,
      candleCount: count,
    );
    expect(guide.index, index);
    expect(guide.x, closeTo(trueX, 1e-9),
        reason: 'The guide is centered on the candle used by the time label');
    final other = ChartCrosshairSnap.resolve(
      viewport: viewport,
      touchX: trueX - 2.2,
      plotWidth: width,
      candleCount: count,
    );
    expect(other.index, index - 1);
    expect(other.x, viewport.chartX(
      index: index - 1, candleCount: count, plotWidth: width));
  });

  test('crosshair follows real 60px close-up candles and no future space',
      () {
    const viewport = ChartViewport(barWidth: ChartViewport.maxBarWidth);
    const width = 320.0;
    const count = 200;
    const index = 199;
    final candleX = viewport.chartX(
        index: index, candleCount: count, plotWidth: width);
    final hit = ChartCrosshairSnap.resolve(
      viewport: viewport, touchX: candleX + 15,
      plotWidth: width, candleCount: count);
    expect(hit.index, index);
    expect(hit.x, candleX);

    const blank = ChartViewport(scrollBars: -15);
    final realX = blank.chartX(
        index: 89, candleCount: 90, plotWidth: 300);
    final real = ChartCrosshairSnap.resolve(
      viewport: blank, touchX: realX + 3,
      plotWidth: 300, candleCount: 90);
    expect(real.index, 89);
    expect(real.x, closeTo(realX, 1e-9));
    final future = ChartCrosshairSnap.resolve(
      viewport: blank, touchX: 280, plotWidth: 300, candleCount: 90);
    expect(future.index, isNull,
        reason: 'Future whitespace must not get a fabricated broker time');
    expect(future.x, 280);
  });

  test('Replay crosshair cannot select candles beyond visible prefix', () {
    const viewport = ChartViewport(barWidth: 10);
    final last = ChartCrosshairSnap.resolve(
      viewport: viewport, touchX: 295,
      plotWidth: 300, candleCount: 4);
    expect(last.index, 3);
    expect(last.x, 295);
    final unseen = ChartCrosshairSnap.resolve(
      viewport: viewport, touchX: 300,
      plotWidth: 300, candleCount: 4);
    expect(unseen.index, isNull,
        reason: 'No forward time label beyond Replay candles');
    expect(ChartCrosshairSnap.resolve(
      viewport: viewport, touchX: 100,
      plotWidth: 300, candleCount: 0).index, isNull);
    expect(ChartCrosshairSnap.resolve(
      viewport: viewport, touchX: double.nan,
      plotWidth: 300, candleCount: 4).index, isNull);
  });

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

  test('time-axis drag zooms around the initial real candle, never pans it',
      () {
    const viewport = ChartViewport(
      barWidth: 10, scrollBars: 38, rightMarginBars: 4);
    const candles = 200;
    const plotWidth = 300.0;
    const sourceIndex = 155;
    final anchorX = viewport.chartX(
      index: sourceIndex, candleCount: candles, plotWidth: plotWidth);
    expect(anchorX, closeTo(195, .000001));

    final closer = viewport.dragTimeAxis(
      deltaX: 80, anchorX: anchorX,
      plotWidth: plotWidth, candleCount: candles);
    expect(closer.barWidth, greaterThan(viewport.barWidth));
    expect(closer.chartX(index: sourceIndex,
        candleCount: candles, plotWidth: plotWidth),
        closeTo(anchorX, 1e-7),
        reason: 'Axis scaling keeps the actual candle under the initial touch');
    expect(closer.indexAt(x: anchorX,
        plotWidth: plotWidth, candleCount: candles), sourceIndex);

    final wider = closer.dragTimeAxis(
      deltaX: -80, anchorX: anchorX,
      plotWidth: plotWidth, candleCount: candles);
    expect(wider.barWidth, closeTo(viewport.barWidth, 1e-9));
    expect(wider.scrollBars, closeTo(viewport.scrollBars, 1e-8));
    expect(wider.chartX(index: sourceIndex,
        candleCount: candles, plotWidth: plotWidth),
        closeTo(anchorX, 1e-7));
  });

  test('time ruler scaling respects original 3–60px candle bounds',
      () {
    const viewport = ChartViewport(barWidth: 10, scrollBars: 80,
      rightMarginBars: 4);
    final close = viewport.dragTimeAxis(
        deltaX: 9000, anchorX: 160, plotWidth: 320, candleCount: 1000);
    expect(close.barWidth, ChartViewport.maxBarWidth);
    final far = viewport.dragTimeAxis(
        deltaX: -9000, anchorX: 160, plotWidth: 320, candleCount: 1000);
    expect(far.barWidth, ChartViewport.minBarWidth);
    for (final state in [close, far]) {
      final (first, end) = state.visibleIndices(
          plotWidth: 320, candleCount: 1000);
      expect(first, inInclusiveRange(0, 1000));
      expect(end, inInclusiveRange(first, 1000),
          reason: 'No invented candles appear when zooming out');
      expect(state.scrollBars, isNonNegative);
    }
  });

  test('time-axis gestures never invent future Replay source or accept NaN',
      () {
    const replay = ChartViewport(barWidth: 10, rightMarginBars: 4);
    const count = 4;
    final wider = replay.dragTimeAxis(
        deltaX: -100, anchorX: 200, plotWidth: 300,
        candleCount: count);
    expect(wider.indexAt(x: 300, plotWidth: 300, candleCount: count),
        isNull, reason: 'Right-hand Replay whitespace is not market history');
    final (start, end) = wider.visibleIndices(
        plotWidth: 300, candleCount: count);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, lessThanOrEqualTo(count));
    expect(identical(replay.dragTimeAxis(
        deltaX: double.nan, anchorX: 150,
        plotWidth: 300, candleCount: count), replay), isTrue);
    expect(identical(replay.dragTimeAxis(
        deltaX: 40, anchorX: double.infinity,
        plotWidth: 300, candleCount: count), replay), isTrue);
    expect(identical(replay.dragTimeAxis(
        deltaX: 40, anchorX: 150,
        plotWidth: double.nan, candleCount: count), replay), isTrue);
    expect(identical(replay.dragTimeAxis(
        deltaX: 40, anchorX: 150,
        plotWidth: 300, candleCount: 0), replay), isTrue);
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
    expect(zoomed.barWidth, ChartViewport.maxBarWidth);
  });

  test('wider mobile pinch keeps actual candle under both focal positions',
      () {
    const plotWidth = 330.0;
    const count = 2000;
    const candleIndex = 1945;
    const initial = ChartViewport(barWidth: 10, scrollBars: 43.5,
      rightMarginBars: 4);
    final originalX = initial.chartX(
        index: candleIndex, candleCount: count, plotWidth: plotWidth);

    // Zoom far in while moving both fingers, as in TradingView mobile.
    final large = initial.pinch(
        scale: 6, initialFocalX: originalX,
        currentFocalX: originalX + 18,
        plotWidth: plotWidth, candleCount: count);
    expect(large.barWidth, 60);
    expect(large.chartX(index: candleIndex, candleCount: count,
        plotWidth: plotWidth), closeTo(originalX + 18, .000001));
    expect(large.indexAt(x: originalX + 18,
        plotWidth: plotWidth, candleCount: count), candleIndex);

    // Pan/zoom back over more broker history without reordering BID/OHLC.
    final small = initial.pinch(
        scale: .3, initialFocalX: originalX,
        currentFocalX: originalX - 10,
        plotWidth: plotWidth, candleCount: count);
    expect(small.barWidth, 3);
    expect(small.chartX(index: candleIndex, candleCount: count,
        plotWidth: plotWidth), closeTo(originalX - 10, .000001));
    expect(small.indexAt(x: originalX - 10,
        plotWidth: plotWidth, candleCount: count), candleIndex);
    final (from, end) = small.visibleIndices(
        plotWidth: plotWidth, candleCount: count);
    expect(from, greaterThanOrEqualTo(0));
    expect(end, lessThanOrEqualTo(count),
        reason: 'Deep zoom out never exposes invented future candles');
    expect(end - from, greaterThan(90));
  });

  test('extreme zoom preserves bounded price and time axes on short history',
      () {
    const initial = ChartViewport(scrollBars: 0, rightMarginBars: 4);
    const count = 4;
    final zoomOut = initial.pinch(scale: .001,
        initialFocalX: 160, currentFocalX: 160,
        plotWidth: 320, candleCount: count);
    expect(zoomOut.barWidth, ChartViewport.minBarWidth);
    expect(zoomOut.scrollBars, inInclusiveRange(-72.6, 3));
    final zoomIn = initial.pinch(scale: 10000,
        initialFocalX: 160, currentFocalX: 160,
        plotWidth: 320, candleCount: count);
    expect(zoomIn.barWidth, ChartViewport.maxBarWidth);
    final (start, end) = zoomIn.visibleIndices(
        plotWidth: 320, candleCount: count);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, lessThanOrEqualTo(count));
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

  test('active Replay without anchored overlays uses painter-only gestures', () {
    bool paintOnly({
      bool selecting = false,
      bool crosshair = false,
      bool draggingDrawing = false,
      bool rectangles = false,
      bool rectanglesTrackViewport = false,
      bool practiceLevels = false,
      bool practiceLevelsTrackViewport = false,
    }) =>
        chartCanUsePaintOnlyViewportUpdate(
          selectingReplayStart: selecting,
          crosshairVisible: crosshair,
          movingDrawing: draggingDrawing,
          visiblePriceRectangles: rectangles,
          priceRectanglesFollowViewport: rectanglesTrackViewport,
          replayTradeLevelsVisible: practiceLevels,
          replayTradeLevelsFollowViewport: practiceLevelsTrackViewport,
        );

    expect(paintOnly(), isTrue,
        reason: 'Replay without overlays should not rebuild the whole screen');
    expect(paintOnly(selecting: true), isFalse,
        reason: 'Blue Replay selection cursor must follow the viewport');
    expect(paintOnly(crosshair: true), isFalse);
    expect(paintOnly(draggingDrawing: true), isFalse);
    expect(paintOnly(rectangles: true), isFalse,
        reason: 'Snapshot-based rectangles still require a full rebuild');
    expect(paintOnly(rectangles: true, rectanglesTrackViewport: true), isTrue,
        reason: 'Bound rectangle layer repaints without rebuilding controls');
    expect(paintOnly(selecting: true, rectangles: true,
        rectanglesTrackViewport: true), isFalse,
        reason: 'Selecting Replay start must still update its cursor widget');
    expect(paintOnly(practiceLevels: true), isFalse,
        reason: 'Static Replay entry, stop and target need rebuilding');
    expect(paintOnly(practiceLevels: true, practiceLevelsTrackViewport: true),
        isTrue,
        reason: 'When price levels repaint with the moving chart, no '
            'toolbar rebuild is required');
    expect(paintOnly(rectangles: true,
        practiceLevels: true, practiceLevelsTrackViewport: true), isFalse,
        reason: 'Unbound rectangles remain unsafe even when trades track pan');
    expect(paintOnly(rectangles: true, rectanglesTrackViewport: true,
        practiceLevels: true, practiceLevelsTrackViewport: true), isTrue,
        reason: 'Both independent layers can paint with the live chart');
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
