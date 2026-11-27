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

  test('invalid Android touch samples never select a phantom source bar', () {
    const viewport = ChartViewport(
        barWidth: 10, scrollBars: 12, rightMarginBars: 4);
    const sourceCount = 160;
    final x = viewport.chartX(
        index: 135, candleCount: sourceCount, plotWidth: 320);
    expect(viewport.indexAt(
        x: x, plotWidth: 320, candleCount: sourceCount), 135);
    for (final invalid in <double>[
      double.nan, double.infinity, double.negativeInfinity
    ]) {
      expect(viewport.indexAt(x: invalid, plotWidth: 320,
          candleCount: sourceCount), isNull);
      expect(viewport.indexAt(x: x, plotWidth: invalid,
          candleCount: sourceCount), isNull);
      expect(identical(viewport.pan(deltaX: invalid,
          plotWidth: 320, candleCount: sourceCount), viewport), isTrue);
      expect(identical(viewport.pinch(scale: invalid,
          initialFocalX: 130, currentFocalX: 130,
          plotWidth: 320, candleCount: sourceCount), viewport), isTrue);
      expect(identical(viewport.pinch(scale: 1.5,
          initialFocalX: invalid, currentFocalX: 130,
          plotWidth: 320, candleCount: sourceCount), viewport), isTrue);
      expect(identical(viewport.pinch(scale: 1.5,
          initialFocalX: 130, currentFocalX: invalid,
          plotWidth: 320, candleCount: sourceCount), viewport), isTrue);
      expect(viewport.visibleIndices(plotWidth: invalid,
          candleCount: sourceCount), (0, 0));
    }
    expect(viewport.indexAt(x: x, plotWidth: 0,
        candleCount: sourceCount), isNull);
    expect(identical(viewport.pan(deltaX: 12, plotWidth: 0,
        candleCount: sourceCount), viewport), isTrue);
    expect(identical(viewport.pinch(scale: 0,
        initialFocalX: 130, currentFocalX: 130,
        plotWidth: 320, candleCount: sourceCount), viewport), isTrue);
    expect(viewport.visibleIndices(plotWidth: 0,
        candleCount: sourceCount), (0, 0));
    // No coordinate normalization should mutate the stored viewport.
    expect(viewport.scrollBars, 12);
    expect(viewport.indexAt(x: x, plotWidth: 320,
        candleCount: sourceCount), 135);
  });

  test('invalid pointer centroid is ignored and valid two-finger pinch recovers',
      () {
    final gesture = ChartTouchGesture();
    const initial = ChartViewport(barWidth: 10, scrollBars: 25);
    ChartViewport update(ChartViewport v, {
      required int pointers,
      required double focal,
      required double scale,
    }) => gesture.update(
      viewport: v, pointerCount: pointers, focalX: focal,
      scale: scale, deltaX: 0, plotWidth: 320, candleCount: 160,
    );

    final invalid = update(initial, pointers: 2,
        focal: double.nan, scale: 1);
    expect(identical(invalid, initial), isTrue);
    expect(gesture.hadMultiTouch, isTrue);
    expect(gesture.ignoredPointerTransition, isTrue);
    final firstValid = update(invalid, pointers: 2,
        focal: 150, scale: 1.0);
    expect(identical(firstValid, initial), isTrue,
        reason: 'First valid sample establishes a new pinch origin');
    final zoomed = update(firstValid, pointers: 2,
        focal: 154, scale: 1.5);
    expect(zoomed.barWidth, closeTo(15, 1e-10));
    expect(zoomed.scrollBars.isFinite, isTrue);
    expect(gesture.ignoredPointerTransition, isFalse);
    final lifted = update(zoomed, pointers: 1,
        focal: 154, scale: 1.0);
    expect(identical(lifted, zoomed), isTrue,
        reason: 'Lifting the second finger cannot jump the candle viewport');
    final pan = gesture.update(
      viewport: lifted, pointerCount: 1,
      focalX: 156, scale: 1, deltaX: 15,
      plotWidth: 320, candleCount: 160,
    );
    expect(pan.scrollBars, greaterThan(lifted.scrollBars),
        reason: 'Valid one-finger panning still works after a bad pinch sample');
  });

  test('first corrupted two-finger sample followed by lift cannot pan', () {
    for (final (focal, scale) in <(double, double)>[
      (double.nan, 1),
      (140, double.infinity),
      (140, 0),
    ]) {
      final gesture = ChartTouchGesture();
      const initial = ChartViewport(
          barWidth: 12, scrollBars: 40, rightMarginBars: 3);
      ChartViewport sample(ChartViewport viewport, int pointers,
          double dx, double sampleFocal, double sampleScale) =>
          gesture.update(
            viewport: viewport, pointerCount: pointers,
            deltaX: dx, focalX: sampleFocal, scale: sampleScale,
            plotWidth: 320, candleCount: 500,
          );
      final corrupted = sample(initial, 2, 0, focal, scale);
      expect(identical(corrupted, initial), isTrue);
      expect(gesture.hadMultiTouch, isTrue);
      expect(gesture.ignoredPointerTransition, isTrue);
      final lifted = sample(corrupted, 1, 175, 290, 1);
      expect(identical(lifted, initial), isTrue,
          reason: 'Pointer handoff must ignore its fake 175px delta');
      expect(gesture.ignoredPointerTransition, isTrue);
      expect(gesture.horizontalTravel, 0,
          reason: 'Synthetic handoff must not qualify as a pan or fling');
      final deliberatePan = sample(lifted, 1, 12, 291, 1);
      expect(deliberatePan.scrollBars,
          closeTo(initial.scrollBars + 1, .0000001));
      expect(deliberatePan.barWidth, initial.barWidth);
      expect(gesture.horizontalTravel, 12);
    }
  });

  test('corrupt first pinch and reentry still zoom around the fresh anchor',
      () {
    final gesture = ChartTouchGesture();
    const original = ChartViewport(barWidth: 10, scrollBars: 35);
    ChartViewport sample(ChartViewport viewport, int pointers,
        double focal, double scale, double dx) => gesture.update(
          viewport: viewport, pointerCount: pointers,
          focalX: focal, scale: scale, deltaX: dx,
          plotWidth: 320, candleCount: 500,
        );

    final invalid = sample(original, 2, double.nan, 1, 0);
    final firstValid = sample(invalid, 2, 150, 1.3, 0);
    expect(identical(firstValid, original), isTrue);
    final zoomed = sample(firstValid, 2, 155, 2.6, 0);
    expect(zoomed.barWidth, 20);
    final lifted = sample(zoomed, 0, 290, 1, 175);
    expect(identical(lifted, zoomed), isTrue);
    expect(gesture.ignoredPointerTransition, isTrue);
    // A brand-new gesture after releasing all pointers re-anchors rather
    // than using the previous session's scale or focal origin.
    final restarted = sample(lifted, 2, 200, 5, 0);
    expect(identical(restarted, lifted), isTrue);
    final continued = sample(restarted, 2, 202, 5.5, 0);
    expect(continued.barWidth, closeTo(22, 1e-10));
    expect(continued.scrollBars.isFinite, isTrue);
  });

  test('invalid Android centroid mid-pinch rebases at current candle viewport',
      () {
    final gesture = ChartTouchGesture();
    const original = ChartViewport(
        barWidth: 10, scrollBars: 45, rightMarginBars: 3);
    ChartViewport sample(ChartViewport current,
        {required double focal, required double scale, int pointers = 2,
         double deltaX = 0}) => gesture.update(
          viewport: current, pointerCount: pointers,
          focalX: focal, scale: scale, deltaX: deltaX,
          plotWidth: 320, candleCount: 500,
        );

    final started = sample(original, focal: 160, scale: 1);
    expect(identical(started, original), isTrue);
    final zoomed = sample(started, focal: 164, scale: 1.8);
    expect(zoomed.barWidth, closeTo(18, 1e-10));
    expect(gesture.ignoredPointerTransition, isFalse);

    // A bad Android centroid can occur after an established two-finger zoom.
    // It must not undo the valid zoom or keep the now-stale initial anchor.
    final interrupted = sample(zoomed, focal: double.nan, scale: 1.8);
    expect(identical(interrupted, zoomed), isTrue);
    expect(gesture.ignoredPointerTransition, isTrue);
    expect(gesture.hadMultiTouch, isTrue);

    // The next valid Android sample may carry a different centroid and
    // cumulative scale, but is only a new baseline (not an actual gesture).
    final resumed = sample(interrupted, focal: 242, scale: 2.4);
    expect(identical(resumed, zoomed), isTrue,
        reason: 'Finger centroid recovery must not jump old candles');
    expect(gesture.ignoredPointerTransition, isTrue);
    final continued = sample(resumed, focal: 245, scale: 2.64);
    expect(continued.barWidth, closeTo(19.8, 1e-9),
        reason: 'Only the post-recovery scale ratio 2.64/2.4 applies');
    expect(continued.scrollBars.isFinite, isTrue);
    expect(gesture.ignoredPointerTransition, isFalse);

    // Another corrupted scale while zooming has the same restart guarantee.
    final interruptedAgain =
        sample(continued, focal: 245, scale: double.infinity);
    expect(identical(interruptedAgain, continued), isTrue);
    final resumedAgain = sample(interruptedAgain, focal: 280, scale: 3);
    expect(identical(resumedAgain, continued), isTrue);
    final afterRecovery = sample(resumedAgain, focal: 281, scale: 3.3);
    expect(afterRecovery.barWidth, closeTo(21.78, 1e-9));
    final lifted = sample(afterRecovery, focal: 281, scale: 1, pointers: 1);
    expect(identical(lifted, afterRecovery), isTrue);
    expect(gesture.ignoredPointerTransition, isTrue);
    final panned = sample(lifted, focal: 280, scale: 1,
        pointers: 1, deltaX: 12);
    expect(panned.scrollBars, greaterThan(lifted.scrollBars));
  });

  test('direct finger lift after invalid active pinch cannot pan the chart',
      () {
    final gesture = ChartTouchGesture();
    const original = ChartViewport(barWidth: 12, scrollBars: 42);
    ChartViewport sample(ChartViewport current, {
      required int pointers, required double focal,
      required double scale, required double dx,
    }) => gesture.update(
      viewport: current, pointerCount: pointers,
      focalX: focal, scale: scale, deltaX: dx,
      plotWidth: 320, candleCount: 500,
    );
    final began = sample(original,
        pointers: 2, focal: 154, scale: 1, dx: 0);
    final zoomed = sample(began,
        pointers: 2, focal: 158, scale: 1.5, dx: 4);
    expect(zoomed.barWidth, 18);
    final interrupted = sample(zoomed,
        pointers: 2, focal: double.nan, scale: 1.5, dx: 0);
    expect(identical(interrupted, zoomed), isTrue);
    final lifted = sample(interrupted,
        pointers: 1, focal: 300, scale: 1, dx: 142);
    expect(identical(lifted, zoomed), isTrue,
        reason: 'First one-finger frame after a bad pinch is only centroid shift');
    expect(gesture.ignoredPointerTransition, isTrue);
    final panned = sample(lifted,
        pointers: 1, focal: 300, scale: 1, dx: 11);
    expect(panned.scrollBars, greaterThan(lifted.scrollBars),
        reason: 'Deliberate one-finger pan resumes on next valid sample');
  });

  test('bad persisted or transient viewport geometry is not hit-testable', () {
    const invalidWidth = ChartViewport(barWidth: 0);
    const invalidScroll = ChartViewport(scrollBars: double.nan);
    const invalidMargin = ChartViewport(rightMarginBars: double.infinity);
    for (final viewport in [invalidWidth, invalidScroll, invalidMargin]) {
      expect(viewport.indexAt(x: 100, plotWidth: 320,
          candleCount: 10), isNull);
      expect(viewport.visibleIndices(
          plotWidth: 320, candleCount: 10), (0, 0));
      expect(identical(viewport.pan(deltaX: 10,
          plotWidth: 320, candleCount: 10), viewport), isTrue);
      expect(identical(viewport.pinch(scale: 1.3,
          initialFocalX: 100, currentFocalX: 110,
          plotWidth: 320, candleCount: 10), viewport), isTrue);
    }
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
    // A single large Android centroid jump must be rate-limited, not
    // interpreted as an instant jump from 10px to 60px.
    final first = viewport.dragTimeAxis(
        deltaX: 9000, anchorX: 160, plotWidth: 320, candleCount: 1000);
    expect(first.barWidth, lessThan(ChartViewport.maxBarWidth));
    var close = viewport;
    var far = viewport;
    for (var i = 0; i < 6; i++) {
      close = close.dragTimeAxis(
          deltaX: 120, anchorX: 160, plotWidth: 320, candleCount: 1000);
      far = far.dragTimeAxis(
          deltaX: -120, anchorX: 160, plotWidth: 320, candleCount: 1000);
    }
    expect(close.barWidth, ChartViewport.maxBarWidth);
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

  test('Replay reveal ignores invalid geometry instead of jumping history', () {
    // Corrupt persisted chart settings and transient Android geometry must
    // not create a synthetic Replay selection or shift its historical anchor.
    const invalid = <ChartViewport>[
      ChartViewport(barWidth: 0, scrollBars: 12),
      ChartViewport(barWidth: double.nan, scrollBars: 12),
      ChartViewport(barWidth: double.infinity, scrollBars: 12),
      ChartViewport(barWidth: 1e-320, scrollBars: 12),
      ChartViewport(scrollBars: double.nan),
      ChartViewport(scrollBars: double.infinity),
      ChartViewport(rightMarginBars: double.nan),
      ChartViewport(rightMarginBars: double.infinity),
    ];
    for (final viewport in invalid) {
      expect(identical(viewport.revealHistoricalBar(
          index: 18, candleCount: 80, plotWidth: 320), viewport), isTrue);
    }
    const valid = ChartViewport(barWidth: 10, rightMarginBars: 4);
    for (final badWidth in <double>[
      double.nan, double.infinity, double.negativeInfinity, 0,
    ]) {
      expect(identical(valid.revealHistoricalBar(
          index: 85, candleCount: 120, plotWidth: badWidth), valid), isTrue);
    }
    expect(identical(valid.revealHistoricalBar(
        index: 120, candleCount: 120, plotWidth: 320), valid), isTrue);
    final revealed = valid.revealHistoricalBar(
        index: 85, candleCount: 120, plotWidth: 320);
    expect(revealed.chartX(index: 85, candleCount: 120, plotWidth: 320),
        closeTo(160, 1e-9),
        reason: 'A valid authentic Replay candle remains finger-centered');
  });

  test('Range rebase ignores invalid viewport geometry without moving bars', () {
    const invalid = <ChartViewport>[
      ChartViewport(barWidth: 0, scrollBars: 28.75),
      ChartViewport(barWidth: double.nan, scrollBars: 28.75),
      ChartViewport(scrollBars: double.nan),
      ChartViewport(scrollBars: double.infinity),
      ChartViewport(scrollBars: 28.75, rightMarginBars: double.nan),
      ChartViewport(scrollBars: 28.75, rightMarginBars: double.infinity),
    ];
    for (final viewport in invalid) {
      expect(identical(viewport.remapHistoricalAnchor(
          oldCount: 120, oldIndex: 90,
          newCount: 175, newIndex: 141), viewport), isTrue,
          reason: 'Invalid Range anchors cannot jump to a fabricated bar');
    }
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

  test('two-to-three-to-two Android pointers rebase without chart jumps',
      () {
    const plotWidth = 360.0;
    const candles = 500;
    const initial = ChartViewport(barWidth: 10, scrollBars: 100);
    final gesture = ChartTouchGesture();

    ChartViewport update(ChartViewport v, {
      required int pointers, required double focal, required double scale,
      double dx = 0,
    }) => gesture.update(
      viewport: v, pointerCount: pointers, focalX: focal,
      scale: scale, deltaX: dx, plotWidth: plotWidth,
      candleCount: candles,
    );

    final firstTwo = update(initial, pointers: 2, focal: 180, scale: 1);
    expect(identical(firstTwo, initial), isTrue);
    final twoZoom = update(firstTwo, pointers: 2, focal: 190, scale: 2);
    expect(twoZoom.barWidth, closeTo(20, .000001));

    // A third finger changes Flutter's centroid and potentially its scale,
    // but cannot teleport candles or inherit the previous pointer group's
    // origin, even if the transition reports a huge synthetic x-delta.
    final thirdJoined = update(twoZoom, pointers: 3,
        focal: 340, scale: 3.8, dx: 150);
    expect(identical(thirdJoined, twoZoom), isTrue);
    expect(gesture.ignoredPointerTransition, isTrue);
    expect(gesture.horizontalTravel, 0);

    final threeZoom = update(thirdJoined, pointers: 3,
        focal: 190, scale: 4.56);
    expect(threeZoom.barWidth, closeTo(24, .000001),
        reason: 'New group scales 4.56/3.8 relative to CURRENT 20px width');
    expect(threeZoom.scrollBars.isFinite, isTrue);

    // Leaving a third finger still leaves a two-finger pinch, NOT a pan.
    final thirdLifted = update(threeZoom, pointers: 2,
        focal: 25, scale: 2.0, dx: -165);
    expect(identical(thirdLifted, threeZoom), isTrue);
    expect(gesture.ignoredPointerTransition, isTrue);
    final twoResumed = update(thirdLifted, pointers: 2,
        focal: 35, scale: 2.5);
    expect(twoResumed.barWidth, closeTo(30, .000001));
    expect(gesture.horizontalTravel, 0);

    final oneLifted = update(twoResumed, pointers: 1,
        focal: 220, scale: 1, dx: 185);
    expect(identical(oneLifted, twoResumed), isTrue,
        reason: 'The final centroid handoff must not turn into a pan');
    final deliberatePan = update(oneLifted, pointers: 1,
        focal: 225, scale: 1, dx: 15);
    expect(deliberatePan.scrollBars,
        closeTo(oneLifted.scrollBars + .5, .000001));
    expect(gesture.horizontalTravel, closeTo(15, .000001));
    expect(gesture.hadMultiTouch, isTrue,
        reason: 'A previous pinch cannot produce a surprise fling on lift');
  });

  test('invalid three-finger transition resets the prior pinch origin', () {
    final gesture = ChartTouchGesture();
    const v = ChartViewport(barWidth: 12, scrollBars: 40);
    ChartViewport update(ChartViewport from, int pointers, double focal,
        double scale) => gesture.update(
      viewport: from, pointerCount: pointers, focalX: focal,
      scale: scale, deltaX: 120, plotWidth: 320, candleCount: 300,
    );
    final twoStart = update(v, 2, 150, 1);
    final twoZoom = update(twoStart, 2, 151, 1.5);
    expect(twoZoom.barWidth, closeTo(18, .000001));

    final invalidThird = update(twoZoom, 3, double.nan, double.infinity);
    expect(identical(invalidThird, twoZoom), isTrue);
    expect(gesture.ignoredPointerTransition, isTrue);
    final thirdValid = update(invalidThird, 3, 260, 4);
    expect(identical(thirdValid, twoZoom), isTrue,
        reason: 'First valid sample must establish a fresh 3-pointer anchor');
    expect(gesture.ignoredPointerTransition, isTrue);
    final resumed = update(thirdValid, 3, 265, 5);
    expect(resumed.barWidth, closeTo(22.5, .000001));

    final handoff = update(resumed, 2, 90, 1.2);
    expect(identical(handoff, resumed), isTrue,
        reason: '3-to-2 handoff resets even after invalid earlier samples');
    final continued = update(handoff, 2, 95, 1.6);
    expect(continued.barWidth, closeTo(30, .000001));
    expect(gesture.horizontalTravel, 0);
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

  test('blocked historical boundary swipes cannot trigger phantom fling',
      () {
    final gesture = ChartTouchGesture();
    const atOldest = ChartViewport(barWidth: 10, scrollBars: 99);
    final blocked = gesture.update(
      viewport: atOldest, pointerCount: 1, focalX: 140,
      scale: 1, deltaX: 600,
      plotWidth: 300, candleCount: 100,
    );
    expect(blocked.scrollBars, 99);
    expect(gesture.horizontalTravel, 0,
        reason: 'Finger motion past loaded history is not chart travel');
    expect(chartShouldFling(
      horizontalVelocity: 2000,
      horizontalTravel: gesture.horizontalTravel,
      candleCount: 100,
      multiTouch: gesture.hadMultiTouch,
      editingDrawing: false,
      reducedMotion: false,
    ), isFalse,
        reason: 'Avoid momentum work when nothing on the chart moved');

    final clampedGesture = ChartTouchGesture();
    const rightEdge = ChartViewport(barWidth: 10, scrollBars: -20.4);
    final blockedRight = clampedGesture.update(
      viewport: rightEdge, pointerCount: 1, focalX: 170,
      scale: 1, deltaX: -600,
      plotWidth: 300, candleCount: 100,
    );
    expect(blockedRight.scrollBars, closeTo(-20.4, 1e-10));
    expect(clampedGesture.horizontalTravel, 0);
  });

  test('pan travel measures only visible displacement before clamping', () {
    final gesture = ChartTouchGesture();
    const nearOldest = ChartViewport(barWidth: 10, scrollBars: 98.5);
    final clamped = gesture.update(
      viewport: nearOldest, pointerCount: 1, focalX: 150,
      scale: 1, deltaX: 200,
      plotWidth: 300, candleCount: 100,
    );
    expect(clamped.scrollBars, 99);
    expect(gesture.horizontalTravel, closeTo(5, 1e-9));
    expect(chartShouldFling(
      horizontalVelocity: 2000,
      horizontalTravel: gesture.horizontalTravel,
      candleCount: 100,
      multiTouch: false,
      editingDrawing: false,
      reducedMotion: false,
    ), isFalse,
        reason: 'The full 200px finger swipe did not move 200px of bars');

    final ordinary = ChartTouchGesture();
    const centered = ChartViewport(barWidth: 10, scrollBars: 40);
    final moved = ordinary.update(
      viewport: centered, pointerCount: 1, focalX: 150,
      scale: 1, deltaX: 40,
      plotWidth: 300, candleCount: 100,
    );
    expect(moved.scrollBars, 44);
    expect(ordinary.horizontalTravel, closeTo(40, 1e-9));
    expect(chartShouldFling(
      horizontalVelocity: 2000,
      horizontalTravel: ordinary.horizontalTravel,
      candleCount: 100,
      multiTouch: ordinary.hadMultiTouch,
      editingDrawing: false,
      reducedMotion: false,
    ), isTrue);
    final invalidGeometry = ChartTouchGesture();
    invalidGeometry.update(
      viewport: centered, pointerCount: 1, focalX: 150,
      scale: 1, deltaX: 40,
      plotWidth: 0, candleCount: 100,
    );
    expect(invalidGeometry.horizontalTravel, 0);
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
