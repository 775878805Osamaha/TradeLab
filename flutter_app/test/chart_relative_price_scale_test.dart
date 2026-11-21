import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_axis_ticks.dart';
import 'package:tradelab_flutter/chart/chart_price_scale_cache.dart';
import 'package:tradelab_flutter/chart/chart_scale_settings.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  const viewport = ChartViewport(barWidth: 10, rightMarginBars: 4);
  const source = <TradeCandle>[
    TradeCandle(100, 120, 95, 105),
    TradeCandle(110, 140, 100, 120),
  ];

  for (final mode in <ChartPriceReferenceMode>[
    ChartPriceReferenceMode.percent,
    ChartPriceReferenceMode.indexed100,
  ]) {
    for (final inverted in <bool>[false, true]) {
      test('${mode.name} axis uses original first-visible source close '
          'and does not alter candle or drawing geometry, invert=$inverted',
          () {
        final normal = ChartPriceScale.visible(
          source, viewport, 259, 440, inverted: inverted);
        final relative = ChartPriceScale.visible(source, viewport, 259, 440,
            inverted: inverted, referenceMode: mode);
        expect(relative.usesRelativeScale, isTrue);
        expect(relative.referencePrice, 105);
        expect(relative.sourceVisibleStart, 0);
        expect(relative.sourceVisibleEnd, 2);
        expect(relative.sourceMinimum, normal.sourceMinimum);
        expect(relative.sourceMaximum, normal.sourceMaximum);
        for (final marketPrice in <double>[95, 100, 105, 120, 140]) {
          expect(relative.y(marketPrice), closeTo(
              normal.y(marketPrice), 1e-8),
              reason: 'Percent labels must not move candles or real-price tools');
          expect(relative.marketPriceForAxisValue(
              relative.axisValue(marketPrice)),
              closeTo(marketPrice, 1e-8));
          expect(relative.price(relative.y(marketPrice)),
              closeTo(marketPrice, 1e-8));
        }
        expect(relative.axisValue(105),
            mode == ChartPriceReferenceMode.percent ? 0 : 100);
        expect(relative.axisValue(115.5),
            closeTo(mode == ChartPriceReferenceMode.percent ? 10 : 110, 1e-8));
        expect(relative.axisLabel(105, 2),
            mode == ChartPriceReferenceMode.percent ? '0.00%' : '100.00');
        expect(relative.axisLabel(115.5, 1),
            mode == ChartPriceReferenceMode.percent ? '10.0%' : '110.0');

        final manual = relative.dragPriceAxis(
            deltaY: 62, focalY: 190);
        expect(manual.referencePrice, relative.referencePrice);
        expect(manual.referenceMode, mode);
        expect(manual.y(relative.price(190)), closeTo(190, 1e-7),
            reason: 'Manual price ruler must preserve true finger anchor');
        expect(manual.withHeight(540).referenceMode, mode);
        expect(manual.withHeight(540).referencePrice, 105);
      });
    }
  }

  test('current visible historical candle reanchors Percent after pan',
      () {
    final candles = List<TradeCandle>.generate(600, (i) {
      final price = 100.0 + i / 2;
      return TradeCandle(price, price + 1, price - 1, price + .5);
    });
    const newest = ChartViewport(
        barWidth: 10, rightMarginBars: 4);
    const older = ChartViewport(
        barWidth: 10, rightMarginBars: 4, scrollBars: 100);
    final latest = ChartPriceScale.visible(
      candles, newest, 259, 440,
      referenceMode: ChartPriceReferenceMode.percent);
    final past = ChartPriceScale.visible(
      candles, older, 259, 440,
      referenceMode: ChartPriceReferenceMode.percent);
    expect(latest.sourceVisibleStart, isNot(past.sourceVisibleStart));
    expect(latest.referencePrice,
        candles[latest.sourceVisibleStart!].close);
    expect(past.referencePrice, candles[past.sourceVisibleStart!].close);
    expect(latest.referencePrice, isNot(past.referencePrice));
    expect(latest.axisValue(latest.referencePrice!), closeTo(0, 1e-8));
    expect(past.axisValue(past.referencePrice!), closeTo(0, 1e-8));
  });

  test('LOG remains exclusive and invalid nonpositive base remains real',
      () {
    final logarithmic = ChartPriceScale.visible(
        source, viewport, 259, 440, logarithmic: true,
        referenceMode: ChartPriceReferenceMode.percent);
    expect(logarithmic.usesLogarithmic, isTrue);
    expect(logarithmic.usesRelativeScale, isFalse);
    expect(logarithmic.axisLabel(105, 2), '105.00');
    const invalid = <TradeCandle>[
      TradeCandle(-10, 50, -20, 0),
      TradeCandle(1, 20, 1, 5),
    ];
    final regularFallback = ChartPriceScale.visible(
        invalid, viewport, 259, 440,
        referenceMode: ChartPriceReferenceMode.indexed100);
    expect(regularFallback.usesRelativeScale, isFalse);
    expect(regularFallback.sourceMinimum, -20);
    expect(regularFallback.axisValue(5), 5);
    expect(regularFallback.axisLabel(5, 2), '5.00');
  });

  test('one-entry cache separates 4 price scale modes and historical source',
      () {
    final cache = ChartPriceScaleCache();
    ChartPriceScale resolve({
      ChartPriceReferenceMode mode = ChartPriceReferenceMode.price,
      bool log = false,
      List<TradeCandle> candles = source,
    }) => cache.resolve(
      candles: candles, viewport: viewport, plotWidth: 259,
      plotHeight: 440, logarithmic: log, inverted: false,
      referenceMode: mode, topMarginPercent: 8, bottomMarginPercent: 8,
    );
    final original = resolve();
    final percent = resolve(mode: ChartPriceReferenceMode.percent);
    expect(percent.usesRelativeScale, isTrue);
    expect(identical(original, percent), isFalse);
    expect(identical(percent,
        resolve(mode: ChartPriceReferenceMode.percent)), isTrue);
    final indexed = resolve(mode: ChartPriceReferenceMode.indexed100);
    expect(identical(percent, indexed), isFalse);
    expect(indexed.axisValue(105), 100);
    final logarithmic = resolve(log: true);
    expect(logarithmic.usesLogarithmic, isTrue);
    expect(identical(indexed, logarithmic), isFalse);
    expect(resolve().usesRelativeScale, isFalse);
    final replaced = <TradeCandle>[
      const TradeCandle(100, 150, 60, 135),
      const TradeCandle(110, 140, 100, 120),
    ];
    final fresh = resolve(
        candles: replaced, mode: ChartPriceReferenceMode.percent);
    expect(fresh.referencePrice, 135);
  });

  test('relative ruler's ticks convert to real prices and retain intervals',
      () {
    final scale = ChartPriceScale.visible(source, viewport, 259, 440,
        referenceMode: ChartPriceReferenceMode.percent);
    final lower = scale.axisValue(scale.minimum);
    final upper = scale.axisValue(scale.maximum);
    final spacing = ChartAxisTicks.interval(lower, upper,
        desiredIntervals: 9);
    final prices = ChartAxisTicks.ticksWithStep(lower, upper,
        step: spacing).map(scale.marketPriceForAxisValue).toList();
    expect(prices, isNotEmpty);
    for (final actualPrice in prices) {
      expect(actualPrice, greaterThanOrEqualTo(scale.minimum - 1e-8));
      expect(actualPrice, lessThanOrEqualTo(scale.maximum + 1e-8));
      expect(scale.axisLabel(actualPrice, 2), contains('%'));
    }
    final first = prices.first;
    expect(scale.y(first), closeTo(
        ChartPriceScale.visible(source, viewport, 259, 440).y(first), 1e-8));
  });

  test('Replay reference and percentage cannot see future 100k OHLC',
      () {
    const full = <TradeCandle>[
      TradeCandle(100, 110, 95, 105),
      TradeCandle(105, 130, 100, 125),
      TradeCandle(9999, 99999, 4000, 99990),
    ];
    const viewport = ChartViewport();
    for (final mode in <ChartPriceReferenceMode>[
      ChartPriceReferenceMode.percent, ChartPriceReferenceMode.indexed100,
    ]) {
      final scale = ChartPriceScale.visible(
          CandlePrefix(full, 2), viewport, 259, 440,
          referenceMode: mode, inverted: true);
      expect(scale.sourceVisibleEnd, 2);
      expect(scale.sourceMaximum, 130);
      expect(scale.referencePrice, 105);
      expect(scale.maximum, lessThan(1000));
      expect(scale.axisValue(105),
          mode == ChartPriceReferenceMode.percent ? 0 : 100);
      expect(scale.axisLabel(125, 1), isNotEmpty);
    }
  });

  test('saved relative preferences are backward-compatible and distinct',
      () {
    const original = ChartScaleSettings();
    for (final mode in ['نسبة مئوية', 'مؤشر 100']) {
      final saved = original.copyWith(scaleMode: mode);
      expect(ChartScaleSettings.decode(saved.encode()).scaleMode, mode);
    }
    expect(ChartScaleSettings.decode('{}').scaleMode, 'تلقائي');
  });
}
