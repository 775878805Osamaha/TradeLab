import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_ohlc_inspector.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

/// A read-counting, immutable source list proves performance scales with
/// visible candle columns rather than the number of historical broker bars.
class _CountingCandles extends ListBase<TradeCandle> {
  _CountingCandles(this.source);

  final List<TradeCandle> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Verified OHLC history is immutable');

  @override
  TradeCandle operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('Verified OHLC history is immutable');
}

void main() {
  const count = 120000;
  const plotWidth = 320.0;
  const plotHeight = 470.0;
  final firstMs = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;

  final source = List<TradeCandle>.generate(count, (i) {
    // The fixture contains real-shaped but test-only price bars; it is
    // never published as a broker, Replay or demo market-data feed.
    final price = 3900.0 + i * .005;
    return TradeCandle(price, price + .8, price - .6, price + .2);
  }, growable: false);

  test('120k bars: pan and pinch price scans are bounded at every zoom', () {
    final counted = _CountingCandles(source);
    for (final width in <double>[3.0, 10.0, 60.0]) {
      var viewport = ChartViewport(
        barWidth: width, scrollBars: 20000, rightMarginBars: 4);
      for (var frame = 0; frame < 240; frame++) {
        counted.reads = 0;
        final (start, end) = viewport.visibleIndices(
          plotWidth: plotWidth, candleCount: counted.length);
        expect(start, greaterThanOrEqualTo(0));
        expect(end, lessThanOrEqualTo(count));
        expect(end, greaterThan(start));
        // The painter uses this exact viewport-limited price scale on
        // gesture frames. A full 120k scan would violate the read bound.
        final scale = ChartPriceScale.visible(
          counted, viewport, plotWidth, plotHeight);
        expect(scale.minimum.isFinite, isTrue);
        expect(scale.maximum.isFinite, isTrue);
        expect(scale.maximum, greaterThan(scale.minimum));
        expect(counted.reads, lessThanOrEqualTo(260),
          reason: 'Pan/zoom work must be O(screen columns), not O(120k)');

        viewport = viewport.pan(
          deltaX: frame.isEven ? 8 : -7,
          plotWidth: plotWidth,
          candleCount: count,
        );
        if (frame % 12 == 0) {
          viewport = viewport.pinch(
            scale: frame.isEven ? 1.08 : .93,
            initialFocalX: 160,
            currentFocalX: 160,
            plotWidth: plotWidth,
            candleCount: count,
          );
        }
        expect(viewport.scrollBars.isFinite, isTrue);
        expect(viewport.barWidth, inInclusiveRange(3.0, 60.0));
      }
    }
    expect(source, hasLength(count));
  });

  test('120k bars: source candle remains exactly under pinch focal point',
      () {
    const anchorIndex = 100000;
    for (final width in <double>[3, 10, 60]) {
      final starting = ChartViewport(
        barWidth: width, scrollBars: 20000, rightMarginBars: 4);
      final x = starting.chartX(
        index: anchorIndex, candleCount: count, plotWidth: plotWidth);
      expect(x, inInclusiveRange(0.0, plotWidth));
      final zoomed = starting.pinch(
        scale: .85,
        initialFocalX: x,
        currentFocalX: x,
        plotWidth: plotWidth,
        candleCount: count,
      );
      final after = zoomed.chartX(
        index: anchorIndex, candleCount: count, plotWidth: plotWidth);
      expect(after, closeTo(x, 1e-7));
      final panned = zoomed.pan(
        deltaX: 8, plotWidth: plotWidth, candleCount: count);
      final pannedX = panned.chartX(
        index: anchorIndex, candleCount: count, plotWidth: plotWidth);
      expect(pannedX, closeTo(after + 8, 1e-7));
      final selected = panned.indexAt(
        x: pannedX, plotWidth: plotWidth, candleCount: count);
      expect(selected, anchorIndex);
    }
  });

  test('Replay at 120k archive: future candles cannot affect plotted bounds',
      () {
    final counted = _CountingCandles(source);
    final replay = CandlePrefix(counted, 6400);
    const viewport = ChartViewport(
      barWidth: 3, rightMarginBars: 4);
    counted.reads = 0;
    final (start, end) = viewport.visibleIndices(
      plotWidth: plotWidth, candleCount: replay.length);
    expect(end, 6400);
    expect(start, greaterThan(6200));
    final scale = ChartPriceScale.visible(
      replay, viewport, plotWidth, plotHeight);
    expect(scale.maximum.isFinite, isTrue);
    expect(counted.reads, lessThanOrEqualTo(260));
    final lastIndex = replay.length - 1;
    final lastX = viewport.chartX(
      index: lastIndex, candleCount: replay.length, plotWidth: plotWidth);
    final snap = ChartCrosshairSnap.resolve(
      viewport: viewport, touchX: lastX,
      plotWidth: plotWidth, candleCount: replay.length);
    expect(snap.index, lastIndex);

    final time = List<int>.generate(count, (i) => firstMs + i * 60000,
      growable: false);
    final selected = ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: lastX, plotWidth: plotWidth,
      candles: replay, timestampsUtcMs: time);
    expect(selected?.index, lastIndex);
    expect(selected?.utcTimestampMs, time[lastIndex]);
    expect(selected?.candle.close, source[lastIndex].close);
    final future = ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: plotWidth - 1,
      plotWidth: plotWidth, candles: replay, timestampsUtcMs: time);
    expect(future, isNull,
      reason: 'Future whitespace is not a verified Replay candle');
    expect(source[6400].close, isNot(source[lastIndex].close));
  });
}
