import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/chart/chart_price_scale_cache.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('Replay exposes a read-only prefix without copying future candles', () {
    final candles = List<TradeCandle>.generate(
      100000, (index) => TradeCandle(index + 1.0, index + 2.0,
          index + .5, index + 1.5),
    );
    final visible = CandlePrefix(candles, 7);
    expect(visible.length, 7);
    expect(identical(visible[6], candles[6]), isTrue);
    expect(() => visible[7], throwsRangeError);
    expect(() => visible[0] = candles[50], throwsUnsupportedError);
    expect(() => visible.length = 20, throwsUnsupportedError);
  });

  test('Replay prefix length is bounded by available market history', () {
    final source = [const TradeCandle(1, 2, .5, 1.5)];
    expect(CandlePrefix(source, 50).length, 1);
    expect(CandlePrefix(source, -1).length, 0);
  });
  test('Replay prefix cache reuses source identity only at same cutoff', () {
    const candle = TradeCandle(100, 101, 99, 100);
    final original = List<TradeCandle>.filled(
        100000, candle, growable: false);
    final cache = CandlePrefixCache();
    final first = cache.resolve(original, 200);
    expect(first.length, 200);
    expect(identical(first, cache.resolve(original, 200)), isTrue,
        reason: 'Panning without new data must not allocate a prefix');
    final advanced = cache.resolve(original, 201);
    expect(identical(advanced, first), isFalse,
        reason: 'A revealed bar requires a fresh future-safe cutoff');
    expect(advanced.length, 201);
    expect(first.length, 200);
    expect(() => first[200], throwsRangeError,
        reason: 'An older view must never expose a newly revealed bar');
    final rewind = cache.resolve(original, 180);
    expect(rewind.length, 180);
    expect(() => rewind[180], throwsRangeError);

    final replacement = List<TradeCandle>.of(original, growable: false);
    final swapped = cache.resolve(replacement, 180);
    expect(identical(swapped, rewind), isFalse,
        reason: 'An equal-length new broker snapshot cannot reuse stale OHLC');
    expect(identical(swapped, cache.resolve(replacement, 180)), isTrue);
    cache.clear();
    expect(identical(swapped, cache.resolve(replacement, 180)), isFalse);
  });

  test('Stable Replay prefix preserves auto-scale geometry on pan rebuild', () {
    const flat = TradeCandle(100, 101, 99, 100);
    final candles = List<TradeCandle>.filled(
        100, flat, growable: false);
    final prefixCache = CandlePrefixCache();
    final scaleCache = ChartPriceScaleCache();
    const viewport = ChartViewport(barWidth: 10, scrollBars: 0);
    ChartPriceScale scaleFor(CandlePrefix prefix) => scaleCache.resolve(
      candles: prefix, viewport: viewport,
      plotWidth: 320, plotHeight: 400,
      topMarginPercent: 8, bottomMarginPercent: 8,
    );

    final first = prefixCache.resolve(candles, 80);
    final firstScale = scaleFor(first);
    expect(identical(firstScale, scaleFor(prefixCache.resolve(candles, 80))),
        isTrue, reason: 'Same visible broker bars should share price geometry');

    final later = prefixCache.resolve(candles, 81);
    expect(identical(firstScale, scaleFor(later)), isFalse,
        reason: 'A new Replay cutoff must invalidate the cached geometry');
    expect(() => first[80], throwsRangeError);

    final updated = List<TradeCandle>.of(candles, growable: false);
    updated[80] = const TradeCandle(100, 150, 95, 125);
    final replacement = prefixCache.resolve(updated, 81);
    final replacementScale = scaleFor(replacement);
    expect(identical(replacementScale, scaleFor(later)), isFalse);
    expect(replacementScale.sourceMaximum, 150,
        reason: 'New verified history must show its own high/low');
  });

  test('Replay cache keeps only a valid bounded visible prefix', () {
    const flat = TradeCandle(100, 101, 99, 100);
    final cache = CandlePrefixCache();
    final short = <TradeCandle>[flat];
    expect(cache.resolve(short, 500).length, 1);
    expect(cache.resolve(short, -7).length, 0);
    expect(() => cache.resolve(short, -7)[0], throwsRangeError);
  });
}
