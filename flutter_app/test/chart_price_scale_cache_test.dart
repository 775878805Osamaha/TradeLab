import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_price_scale_cache.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

/// Observe source reads without timing assumptions or injecting fake quotes
/// into a production feed. Synthetic OHLC here is test-only geometry.
class _ReadCountCandles extends ListBase<TradeCandle> {
  _ReadCountCandles(this.source);
  final List<TradeCandle> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Published market snapshot is immutable');

  @override
  TradeCandle operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('Published market snapshot is immutable');
}

void main() {
  const plotWidth = 320.0;
  const plotHeight = 470.0;
  final source = List<TradeCandle>.generate(120000, (i) {
    final price = 3900.0 + i * .005;
    return TradeCandle(price, price + .8, price - .6, price + .2);
  }, growable: false);

  test('120k candles: candle, rectangle and replay layers share one scale',
      () {
    final counted = _ReadCountCandles(source);
    final cache = ChartPriceScaleCache();
    const viewport = ChartViewport(
      barWidth: 3, scrollBars: 20000, rightMarginBars: 4);

    ChartPriceScale resolve({ChartViewport v = viewport}) => cache.resolve(
      candles: counted, viewport: v, plotWidth: plotWidth,
      plotHeight: plotHeight,
      topMarginPercent: 8, bottomMarginPercent: 8,
    );

    final first = resolve();
    expect(first.maximum, greaterThan(first.minimum));
    expect(first.height, plotHeight);
    expect(counted.reads, inInclusiveRange(1, 260),
        reason: 'Initial source read must stay within visible columns');
    final initialReads = counted.reads;

    // Each frame has a candle painter and may have several overlays that
    // request this exact scale. None should rescan source OHLC.
    for (var frame = 0; frame < 240; frame++) {
      final candle = resolve();
      final rectangle = resolve();
      final replayTradeLevels = resolve();
      expect(identical(first, candle), isTrue);
      expect(identical(candle, rectangle), isTrue);
      expect(identical(rectangle, replayTradeLevels), isTrue);
    }
    expect(counted.reads, initialReads,
        reason: '720 overlay scale reads must hit the one-entry cache');
    expect(identical(resolve(v: const ChartViewport(
      barWidth: 3, scrollBars: 20000, rightMarginBars: 4)), first), isTrue,
        reason: 'Value-identical paint viewport must use same scale');
    expect(counted.reads, initialReads);

    final moved = viewport.pan(
      deltaX: 9, plotWidth: plotWidth, candleCount: counted.length);
    final movedScale = resolve(v: moved);
    expect(identical(movedScale, first), isFalse);
    expect(movedScale.minimum, isNot(first.minimum),
        reason: 'Changing scroll must recompute real source price bounds');
    expect(counted.reads - initialReads, inInclusiveRange(1, 260));
    expect(identical(resolve(v: moved), movedScale), isTrue);
    cache.clear();
    expect(identical(resolve(v: moved), movedScale), isFalse,
        reason: 'Disposal/reset cannot preserve a previous source snapshot');
  });

  test('zoom, canvas size, margin and snapshot identity invalidate scale', () {
    final cache = ChartPriceScaleCache();
    final candles = <TradeCandle>[
      const TradeCandle(10, 12, 8, 11),
      const TradeCandle(11, 15, 9, 14),
      const TradeCandle(14, 17, 12, 16),
    ];
    const viewport = ChartViewport(barWidth: 10);
    ChartPriceScale resolve({
      List<TradeCandle>? source,
      ChartViewport v = viewport,
      double width = 320,
      double height = 470,
      int top = 8,
      int bottom = 8,
    }) => cache.resolve(
      candles: source ?? candles, viewport: v,
      plotWidth: width, plotHeight: height,
      topMarginPercent: top, bottomMarginPercent: bottom,
    );
    final first = resolve();
    final same = resolve();
    expect(identical(first, same), isTrue);

    expect(identical(resolve(v: const ChartViewport(barWidth: 5)), same),
        isFalse);
    expect(identical(resolve(width: 250), first), isFalse);
    final resized = resolve(height: 700);
    expect(resized.height, 700);
    expect(identical(resized, same), isFalse);
    final newTopMargin = resolve(top: 15);
    expect(newTopMargin.maximum, greaterThan(first.maximum));
    final newBottomMargin = resolve(bottom: 15);
    expect(newBottomMargin.minimum, lessThan(first.minimum));

    final replaced = <TradeCandle>[
      const TradeCandle(10, 12, 8, 11),
      const TradeCandle(11, 15, 9, 14),
      const TradeCandle(14, 500, 12, 16),
    ];
    expect(replaced.length, candles.length);
    final newScale = resolve(source: replaced);
    expect(newScale.maximum, greaterThan(400),
        reason: 'New verified market snapshot cannot reuse old extremes');
    expect(resolve().maximum, lessThan(30));
  });

  test('Replay prefix cannot inherit future price extremes from live chart',
      () {
    final cache = ChartPriceScaleCache();
    final counted = _ReadCountCandles(source);
    const viewport = ChartViewport(
      barWidth: 3, rightMarginBars: 4);
    final full = cache.resolve(
      candles: counted, viewport: viewport,
      plotWidth: plotWidth, plotHeight: plotHeight,
      topMarginPercent: 8, bottomMarginPercent: 8);
    final futureMaximum = full.maximum;
    final replay = CandlePrefix(counted, 6400);
    counted.reads = 0;
    final visible = cache.resolve(
      candles: replay, viewport: viewport,
      plotWidth: plotWidth, plotHeight: plotHeight,
      topMarginPercent: 8, bottomMarginPercent: 8);
    expect(identical(visible, full), isFalse);
    expect(visible.maximum, lessThan(futureMaximum),
        reason: 'Replay must use last revealed source candle, not live OHLC');
    expect(counted.reads, lessThanOrEqualTo(260));

    final cutoff2 = CandlePrefix(counted, 12000);
    final second = cache.resolve(
      candles: cutoff2, viewport: viewport,
      plotWidth: plotWidth, plotHeight: plotHeight,
      topMarginPercent: 8, bottomMarginPercent: 8);
    expect(second.maximum, greaterThan(visible.maximum));
    expect(identical(second, visible), isFalse);
    expect(identical(cache.resolve(
      candles: cutoff2, viewport: viewport,
      plotWidth: plotWidth, plotHeight: plotHeight,
      topMarginPercent: 8, bottomMarginPercent: 8), second), isTrue);
  });

  test('empty or fully offscreen candles retain source scale semantics', () {
    final cache = ChartPriceScaleCache();
    const viewport = ChartViewport();
    final empty = cache.resolve(
      candles: const <TradeCandle>[], viewport: viewport,
      plotWidth: 320, plotHeight: 200,
      topMarginPercent: 8, bottomMarginPercent: 8);
    expect((empty.minimum, empty.maximum, empty.height), (0, 1, 200));
    expect(identical(empty, cache.resolve(
      candles: const <TradeCandle>[], viewport: viewport,
      plotWidth: 320, plotHeight: 200,
      topMarginPercent: 8, bottomMarginPercent: 8)), isTrue);
    final zeroWidth = cache.resolve(
      candles: source, viewport: viewport,
      plotWidth: 0, plotHeight: 200,
      topMarginPercent: 8, bottomMarginPercent: 8);
    expect((zeroWidth.minimum, zeroWidth.maximum), (0, 1));
  });
}
