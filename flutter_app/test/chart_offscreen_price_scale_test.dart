import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_price_scale_cache.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _CountedVerifiedCandles extends ListBase<TradeCandle> {
  _CountedVerifiedCandles(this.original);
  final List<TradeCandle> original;
  int reads = 0;
  @override
  int get length => original.length;
  @override
  set length(int count) => throw UnsupportedError('Immutable broker history');
  @override
  TradeCandle operator [](int index) {
    reads++;
    return original[index];
  }
  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('Immutable broker history');
}

void main() {
  final source = List<TradeCandle>.generate(300, (index) {
    final price = 3880.0 + index * .20;
    return TradeCandle(price, price + 1, price - 1, price + .5);
  }, growable: false);

  test('all-future whitespace keeps REAL cTrader price scale, not 0..1', () {
    const emptyRight = ChartViewport(
        barWidth: 10, scrollBars: -200, rightMarginBars: 30);
    expect(emptyRight.visibleIndices(
        plotWidth: 320, candleCount: source.length),
        (source.length, source.length));
    final scale = ChartPriceScale.visible(
        source, emptyRight, 320, 470);
    expect(scale.minimum, greaterThan(3900));
    expect(scale.maximum, greaterThan(scale.minimum));
    expect(scale.sourceCandles, same(source));
    expect(scale.sourceVisibleEnd, source.length);
    expect(scale.y(source.last.close).isFinite, isTrue);
    expect(scale.crosshairPrice(240), isNotNull);
    // This falls back to an authenticated part of the broker history
    // for AXIS presentation. No extra bar or timestamp was appended.
    expect(source, hasLength(300));
  });

  test('last price scale stays stable during blank-space pan and zoom', () {
    final counted = _CountedVerifiedCandles(source);
    final cache = ChartPriceScaleCache();
    const normal = ChartViewport(barWidth: 10, scrollBars: 12);
    ChartPriceScale read(ChartViewport viewport,
        {List<TradeCandle>? src, double height = 470,
         bool inverted = false}) => cache.resolve(
      candles: src ?? counted, viewport: viewport,
      plotWidth: 320, plotHeight: height,
      inverted: inverted, topMarginPercent: 8, bottomMarginPercent: 8,
    );
    final before = read(normal);
    final afterNormalReads = counted.reads;
    const blank = ChartViewport(
        barWidth: 10, scrollBars: -200, rightMarginBars: 20);
    expect(blank.visibleIndices(plotWidth: 320,
        candleCount: counted.length), (counted.length, counted.length));
    for (var frame = 0; frame < 160; frame++) {
      final offscreen = read(ChartViewport(
          barWidth: 10, scrollBars: -200.0 - frame));
      expect(identical(offscreen, before), isTrue,
          reason: 'Source axis should not flicker to 0-1 or remeasure '
              'a different chart window during future-space pan');
    }
    expect(counted.reads, afterNormalReads,
        reason: 'Repainting 160 empty-space frames must read zero new OHLC');
    final resized = read(blank, height: 620);
    expect(resized.minimum, before.minimum);
    expect(resized.maximum, before.maximum);
    expect(resized.height, 620);

    final inverted = read(blank, inverted: true);
    expect(inverted.inverted, isTrue,
      reason: 'A real scale-mode change must not inherit old orientation');

    final replaced = List<TradeCandle>.generate(300, (i) =>
        TradeCandle(120, 125, 115, 123), growable: false);
    final fromNewBroker = read(blank, src: replaced);
    expect(fromNewBroker.maximum, lessThan(150),
        reason: 'No last price scale leakage across new source identity');
  });

  test('scrolling before oldest loaded candle uses oldest verified prices', () {
    const beforeOldest = ChartViewport(
        barWidth: 10, scrollBars: 1000, rightMarginBars: 0);
    expect(beforeOldest.visibleIndices(
        plotWidth: 320, candleCount: source.length), (0, 0));
    final scale = ChartPriceScale.visible(
        source, beforeOldest, 320, 470);
    expect(scale.minimum, greaterThan(3800));
    expect(scale.maximum, lessThan(3900),
        reason: 'Offscreen older history must not use an unrelated newest bar');
    expect(scale.sourceVisibleStart, 0);
    expect(scale.sourceVisibleEnd, greaterThan(0));
    expect(source.length, 300);
  });

  test('Replay offscreen price scale reads revealed prefix, not live future', () {
    final all = <TradeCandle>[
      for (var i = 0; i < 20; i++)
        TradeCandle(100.0 + i, 102.0 + i, 99.0 + i, 101.0 + i),
      const TradeCandle(20000, 90000, 19000, 90000),
    ];
    final prefix = CandlePrefix(all, 20);
    const blank = ChartViewport(
        barWidth: 10, scrollBars: -200, rightMarginBars: 30);
    final replay = ChartPriceScale.visible(prefix, blank, 320, 470);
    expect(replay.maximum, lessThan(150),
        reason: 'Future broker price cannot enter Replay axis fallback');
    expect(prefix.length, 20);
    final full = ChartPriceScale.visible(all, blank, 320, 470);
    expect(full.maximum, greaterThan(90000));
  });

  test('fallback for 120k broker bars remains bounded to visible window', () {
    final big = _CountedVerifiedCandles(
      List<TradeCandle>.generate(120000, (i) {
        final price = 2000.0 + i * .01;
        return TradeCandle(price, price + .1, price - .1, price);
      }, growable: false));
    const blank = ChartViewport(
        barWidth: 3, scrollBars: -500, rightMarginBars: 4);
    final scale = ChartPriceScale.visible(big, blank, 320, 480);
    expect(scale.maximum, greaterThan(3000));
    expect(big.reads, lessThan(260),
      reason: 'Price fallback must never scan 120k offscreen OHLC');
  });

  test('truly missing source or invalid plot still has no implied price', () {
    const bad = ChartViewport(barWidth: double.nan);
    final scale = ChartPriceScale.visible(source, bad, 320, 470);
    expect((scale.minimum, scale.maximum), (0, 1));
    final empty = ChartPriceScale.visible(
      const <TradeCandle>[], const ChartViewport(), 320, 470);
    expect((empty.minimum, empty.maximum), (0, 1));
    final missingPlot = ChartPriceScale.visible(
        source, const ChartViewport(), 0, 470);
    expect((missingPlot.minimum, missingPlot.maximum), (0, 1));
  });
}
