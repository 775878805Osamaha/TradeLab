import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_axis_source_labels.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

/// Measures price-source touches without device-FPS claims. These synthetic
/// OHLCs are only test geometry, never published as cTrader market candles.
class _CountingCandles extends ListBase<TradeCandle> {
  _CountingCandles(this.source);
  final List<TradeCandle> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Verified market history cannot be mutated');

  @override
  TradeCandle operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('Verified market history cannot be mutated');
}

void main() {
  final source = List<TradeCandle>.generate(120000, (i) {
    final price = 3900.0 + i * .005;
    return TradeCandle(price, price + .8, price - .6, price + .2);
  }, growable: false);

  test('120k source: unpadded high/low label adds zero duplicate OHLC reads',
      () {
    final candles = _CountingCandles(source);
    const viewport = ChartViewport(
      barWidth: 3, scrollBars: 20000, rightMarginBars: 4);
    const plotWidth = 320.0;
    final (start, end) = viewport.visibleIndices(
        plotWidth: plotWidth, candleCount: candles.length);
    final scale = ChartPriceScale.visible(
      candles, viewport, plotWidth, 470,
      topMarginPercent: 12, bottomMarginPercent: 9);
    final initialReads = candles.reads;
    expect(initialReads, inInclusiveRange(1, 260));

    final original = ChartAxisSourceLabels.visibleHighLow(
      candles, start, end);
    expect(candles.reads, greaterThan(initialReads));
    expect(original, isNotNull);
    candles.reads = 0;

    for (var frame = 0; frame < 240; frame++) {
      final highLow = ChartAxisSourceLabels.visibleHighLowForPaint(
        source: candles,
        displayed: candles,
        scale: scale,
        start: start,
        end: end);
      expect(highLow, original,
          reason: 'Axis annotation must be pixel/price-identical');
    }
    expect(candles.reads, 0,
        reason: 'Repeated pan/pinch repaint labels must reuse scanned OHLC');
    expect(scale.sourceMaximum, original!.$1);
    expect(scale.sourceMinimum, original!.$2);
    expect(scale.maximum, greaterThan(original.$1));
    expect(scale.minimum, lessThan(original.$2));
  });

  test('Heikin Ashi uses original OHLC, never smoothed visual extrema',
      () {
    const actual = <TradeCandle>[
      TradeCandle(100, 105, 95, 101),
      TradeCandle(101, 150, 80, 110),
      TradeCandle(110, 120, 105, 115),
    ];
    const smoothed = <TradeCandle>[
      TradeCandle(99, 103, 97, 100),
      TradeCandle(100, 108, 92, 104),
      TradeCandle(104, 109, 100, 108),
    ];
    const viewport = ChartViewport();
    final displayedScale = ChartPriceScale.visible(
      smoothed, viewport, 320, 470);
    final actualExtremes = ChartAxisSourceLabels.visibleHighLow(
      actual, 0, actual.length);
    expect(ChartAxisSourceLabels.visibleHighLowForPaint(
      source: actual, displayed: smoothed, scale: displayedScale,
      start: 0, end: actual.length), actualExtremes);
    expect(actualExtremes, (150.0, 80.0));
    expect(displayedScale.sourceMaximum, 109);
  });

  test('manual scale, stale source and different window never reuse extrema',
      () {
    const original = <TradeCandle>[
      TradeCandle(100, 105, 95, 101),
      TradeCandle(101, 106, 98, 105),
    ];
    const replaced = <TradeCandle>[
      TradeCandle(100, 205, 95, 101),
      TradeCandle(101, 206, 98, 105),
    ];
    const viewport = ChartViewport();
    final auto = ChartPriceScale.visible(
      original, viewport, 320, 470);
    const manual = ChartPriceScale(50, 500, 470);
    expect(ChartAxisSourceLabels.visibleHighLowForPaint(
      source: original, displayed: original, scale: manual,
      start: 0, end: 2), (106.0, 95.0));
    expect(ChartAxisSourceLabels.visibleHighLowForPaint(
      source: replaced, displayed: replaced, scale: auto,
      start: 0, end: 2), (206.0, 95.0),
      reason: 'Equal-length fresh verified data invalidates old bounds');
    expect(ChartAxisSourceLabels.visibleHighLowForPaint(
      source: original, displayed: original, scale: auto,
      start: 1, end: 2), (106.0, 98.0),
      reason: 'Different visible source indices must not share old maximum');
    expect(auto.sourceVisibleStart, 0);
    expect(auto.sourceVisibleEnd, 2);
    expect(auto.sourceCandles, same(original));
  });

  test('Replay prefix high/low excludes all hidden future source candles',
      () {
    final data = _CountingCandles(source);
    final future = source[110000].high;
    const viewport = ChartViewport(
        barWidth: 3, rightMarginBars: 4);
    final replay = CandlePrefix(data, 6400);
    final (start, end) = viewport.visibleIndices(
      plotWidth: 320, candleCount: replay.length);
    expect(end, 6400);
    final scale = ChartPriceScale.visible(
      replay, viewport, 320, 470);
    data.reads = 0;
    final extremes = ChartAxisSourceLabels.visibleHighLowForPaint(
      source: replay, displayed: replay, scale: scale,
      start: start, end: end);
    expect(data.reads, 0);
    expect(extremes, isNotNull);
    expect(extremes!.$1, lessThan(future));
    expect(extremes, ChartAxisSourceLabels.visibleHighLow(
      replay, start, end));
    expect(scale.sourceCandles, same(replay));

    // A new visible Replay cutoff is a different list and must not inherit
    // a previously computed high/low (even if index range happens to match).
    final extended = CandlePrefix(data, 12000);
    final (nextStart, nextEnd) = viewport.visibleIndices(
      plotWidth: 320, candleCount: extended.length);
    final expected = ChartAxisSourceLabels.visibleHighLow(
      extended, nextStart, nextEnd);
    expect(ChartAxisSourceLabels.visibleHighLowForPaint(
      source: extended, displayed: extended, scale: scale,
      start: nextStart, end: nextEnd), expected);
    expect(expected!.$1, greaterThan(extremes!.$1));
  });

  test('empty/offscreen source preserves legacy no-axis-label behavior',
      () {
    const empty = <TradeCandle>[];
    const viewport = ChartViewport();
    final emptyScale = ChartPriceScale.visible(empty, viewport, 320, 470);
    expect(emptyScale.sourceCandles, isNull);
    expect(ChartAxisSourceLabels.visibleHighLowForPaint(
      source: empty, displayed: empty, scale: emptyScale,
      start: 0, end: 0), isNull);
    expect(ChartAxisSourceLabels.visibleHighLowForPaint(
      source: source, displayed: source, scale: emptyScale,
      start: 20, end: 20), isNull);
  });
}
