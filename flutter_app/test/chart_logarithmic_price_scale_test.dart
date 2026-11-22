import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_axis_ticks.dart';
import 'package:tradelab_flutter/chart/chart_price_scale_cache.dart';
import 'package:tradelab_flutter/chart/chart_scale_settings.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  const viewport = ChartViewport(barWidth: 10, rightMarginBars: 4);
  const width = 329.0;
  const height = 440.0;

  test('LOG gives equal plot space to equal price ratios, without OHLC changes',
      () {
    const source = <TradeCandle>[
      TradeCandle(10, 1000, 10, 100),
    ];
    final scale = ChartPriceScale.visible(
        source, viewport, width, height, logarithmic: true);
    expect(scale.usesLogarithmic, isTrue);
    expect(scale.sourceMinimum, 10);
    expect(scale.sourceMaximum, 1000);
    expect(scale.y(10) - scale.y(100),
        closeTo(scale.y(100) - scale.y(1000), 1e-8));
    for (final marketPrice in <double>[10, 12.5, 100, 410, 1000]) {
      expect(scale.price(scale.y(marketPrice)),
          closeTo(marketPrice, marketPrice * 1e-10));
    }
    expect(source.single.low, 10);
    expect(source.single.high, 1000);
    expect(scale.withHeight(620).usesLogarithmic, isTrue);
    expect(scale.withHeight(620).price(
        scale.withHeight(620).y(410)), closeTo(410, 1e-8));
  });

  test('LOG ruler drag keeps finger price fixed and never produces zero',
      () {
    const source = <TradeCandle>[TradeCandle(30, 900, 20, 800)];
    final scale = ChartPriceScale.visible(
        source, viewport, width, height, logarithmic: true);
    final focusY = height * .38;
    final fingerPrice = scale.price(focusY);
    final after = scale.dragPriceAxis(deltaY: -70, focalY: focusY);
    expect(after.usesLogarithmic, isTrue);
    expect(after.minimum, greaterThan(0));
    expect(after.maximum, greaterThan(after.minimum));
    expect(after.y(fingerPrice), closeTo(focusY, 1e-7));
    expect(after.price(after.y(80)), closeTo(80, 1e-8));
    expect(after.dragPriceAxis(deltaY: double.nan, focalY: focusY),
        same(after));
    expect(after.crosshairPrice(double.infinity), isNull);
    expect(after.crosshairPrice(height * .6), isNotNull);
    expect(after.crosshairPrice(height * .6)!, greaterThan(0));
  });

  test('LOG rejects nonpositive source range without artificial prices', () {
    const source = <TradeCandle>[
      TradeCandle(-10, 20, -15, 10),
      TradeCandle(10, 30, 0, 15),
    ];
    final fallback = ChartPriceScale.visible(
        source, viewport, width, height, logarithmic: true);
    expect(fallback.usesLogarithmic, isFalse);
    expect(fallback.sourceMinimum, -15);
    expect(fallback.sourceMaximum, 30);
    expect(fallback.y(0).isFinite, isTrue);
    expect(fallback.price(fallback.y(0)), closeTo(0, 1e-9));

    final positive = ChartPriceScale.visible(
        const <TradeCandle>[TradeCandle(20, 100, 10, 60)],
        viewport, width, height, logarithmic: true);
    expect(positive.usesLogarithmic, isTrue);
    expect(positive.y(0).isFinite, isTrue);
    expect(positive.y(-200), greaterThan(height),
        reason: 'Historical negative drawing levels stay off the plot');
  });

  test('cache key includes logarithmic mode and source snapshot identity',
      () {
    const bars = <TradeCandle>[
      TradeCandle(20, 30, 19, 25),
      TradeCandle(100, 300, 90, 200),
    ];
    final cache = ChartPriceScaleCache();
    ChartPriceScale resolve({bool logarithmic = false,
        List<TradeCandle> source = bars}) => cache.resolve(
      candles: source, viewport: viewport, plotWidth: width,
      plotHeight: height,
      topMarginPercent: 8, bottomMarginPercent: 8,
      logarithmic: logarithmic,
    );
    final linear = resolve();
    expect(linear.usesLogarithmic, isFalse);
    final log = resolve(logarithmic: true);
    expect(identical(linear, log), isFalse);
    expect(log.usesLogarithmic, isTrue);
    expect(identical(log, resolve(logarithmic: true)), isTrue);
    expect(identical(linear, resolve()), isFalse,
        reason: 'Going back to linear must not reuse a stale LOG transform');
    expect(identical(resolve(), resolve()), isTrue);
    expect(log.sourceMinimum, linear.sourceMinimum);
    expect(log.sourceMaximum, linear.sourceMaximum);
  });

  test('Replay LOG cannot access future broker candle extremes', () {
    const all = <TradeCandle>[
      TradeCandle(100, 110, 90, 106),
      TradeCandle(110, 120, 100, 116),
      TradeCandle(1000, 9999, 980, 8000),
    ];
    final prefix = CandlePrefix(all, 2);
    final scale = ChartPriceScale.visible(
        prefix, viewport, width, height, logarithmic: true);
    expect(scale.usesLogarithmic, isTrue);
    expect(scale.sourceMaximum, 120);
    expect(scale.sourceMinimum, 90);
    expect(scale.maximum, lessThan(1000));
    expect(scale.sourceVisibleEnd, 2);
  });

  test('logarithmic ruler emits bounded, positive, increasing prices', () {
    final values = ChartAxisTicks.logarithmicTicks(1, 1e12).toList();
    expect(values, isNotEmpty);
    expect(values.length, lessThanOrEqualTo(60));
    expect(values.every((e) => e > 0 && e.isFinite), isTrue);
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThan(values[i - 1]));
    }
    expect(ChartAxisTicks.logarithmicTicks(1, 100).toList(),
        containsAll([1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]));
    expect(ChartAxisTicks.logarithmicTicks(0, 100), isEmpty);
    expect(ChartAxisTicks.logarithmicTicks(
        double.nan, 100), isEmpty);
    expect(ChartAxisTicks.logarithmicTicks(1, math.exp(0)), isEmpty);
    final forex = ChartAxisTicks.logarithmicTicks(1.0000, 1.0030).toList();
    expect(forex.length, greaterThan(1),
        reason: 'Narrow Forex LOG windows still need legible ticks');
    expect(forex.every((x) => x >= 1 && x <= 1.003), isTrue);
  });

  test('linear/LOG preferences survive process restart and cancel', () {
    const normal = ChartScaleSettings();
    expect(normal.scaleMode, 'تلقائي');
    final log = normal.copyWith(scaleMode: 'لوغاريتمي');
    expect(ChartScaleSettings.decode(log.encode()).scaleMode, 'لوغاريتمي');
    expect(ChartScaleSettings.decode(normal.encode()).scaleMode, 'تلقائي');
    expect(normal.scaleMode, 'تلقائي');
  });  test('prepared LOG painter projection matches authoritative source y pixels',
      () {
    for (final reversed in <bool>[false, true]) {
      for (final chartHeight in <double>[320, 390, 640]) {
        final scale = ChartPriceScale(1.0001, 120000, chartHeight,
            logarithmic: true, inverted: reversed);
        expect(scale.usesLogarithmic, isTrue);
        final prepared = scale.prepareYForFrame();
        for (final price in <double>[
          -100, 0, 0.0001, 1.0001, 1.001, 24.5, 375, 4000, 120000,
          240000, double.infinity,
        ]) {
          final actual = prepared(price);
          final original = scale.y(price);
          if (original.isInfinite) {
            expect(actual, original);
          } else {
            expect(actual, closeTo(original, 1e-10),
              reason: 'LOG/inverted candles, wicks, labels and drawings '
                  'must retain the same true market-price Y geometry');
          }
        }
        expect(prepared(double.nan).isNaN, isTrue);
        // No new source prices: this is geometry over authentic inputs only.
        expect(scale.price(prepared(4000)), closeTo(4000, 1e-8));
      }
    }
  });

  test('prepared painter keeps linear, Percent, Indexed and LOG fallback',
      () {
    const modes = <ChartPriceReferenceMode>[
      ChartPriceReferenceMode.price,
      ChartPriceReferenceMode.percent,
      ChartPriceReferenceMode.indexed100,
    ];
    for (final mode in modes) {
      for (final inverted in <bool>[false, true]) {
        final scale = ChartPriceScale(10, 1000, 320,
          referenceMode: mode, referencePrice: 50, inverted: inverted);
        final prepared = scale.prepareYForFrame();
        for (final price in <double>[-1, 0, 10, 50, 100, 1000]) {
          expect(prepared(price), scale.y(price));
        }
      }
    }
    // An invalid/nonpositive LOG viewport must not silently re-enable LOG.
    const fallback = ChartPriceScale(-10, 100, 390, logarithmic: true);
    expect(fallback.usesLogarithmic, isFalse);
    expect(fallback.prepareYForFrame()(15), fallback.y(15));
    const zeroHeight = ChartPriceScale(10, 100, 0, logarithmic: true);
    expect(zeroHeight.prepareYForFrame()(30).isFinite,
        zeroHeight.y(30).isFinite);
  });


}
