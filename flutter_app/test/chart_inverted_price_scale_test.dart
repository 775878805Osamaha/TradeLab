import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_price_scale_cache.dart';
import 'package:tradelab_flutter/chart/chart_scale_settings.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  const width = 329.0;
  const height = 440.0;
  const viewport = ChartViewport(rightMarginBars: 4);
  const candles = <TradeCandle>[
    TradeCandle(110, 1200, 10, 950),
    TradeCandle(200, 900, 20, 500),
  ];

  for (final log in <bool>[false, true]) {
    test('inverted ${log ? 'LOG' : 'linear'} map is the vertical mirror'
        ' of source candle and drawing coordinates', () {
      final regular = ChartPriceScale.visible(candles, viewport,
          width, height, logarithmic: log);
      final inverted = ChartPriceScale.visible(candles, viewport,
          width, height, logarithmic: log, inverted: true);
      expect(inverted.inverted, isTrue);
      expect(inverted.usesLogarithmic, log);
      expect(inverted.sourceMinimum, regular.sourceMinimum);
      expect(inverted.sourceMaximum, regular.sourceMaximum);
      for (final price in <double>[10, 20, 110, 300, 950, 1200]) {
        expect(inverted.y(price), closeTo(
            height - regular.y(price), 1e-8));
        expect(inverted.price(inverted.y(price)),
            closeTo(price, price * 1e-9));
        expect(inverted.crosshairPrice(inverted.y(price)), isNotNull);
      }
      expect(inverted.y(1200), greaterThan(inverted.y(10)));
      expect(regular.y(1200), lessThan(regular.y(10)));
      expect(inverted.withHeight(700).inverted, isTrue);
      expect(inverted.withHeight(700).usesLogarithmic, log);
      expect(inverted.withHeight(700).price(
        inverted.withHeight(700).y(300)), closeTo(300, 1e-8));
    });

    test('inverted ${log ? 'LOG' : 'linear'} price-axis gesture retains'
        ' the touched source price at its exact screen y', () {
      final scale = ChartPriceScale.visible(candles,
          viewport, width, height, logarithmic: log, inverted: true);
      final focalY = height * .3;
      final marketPrice = scale.price(focalY);
      final after = scale.dragPriceAxis(
          deltaY: -85, focalY: focalY);
      expect(after.inverted, isTrue);
      expect(after.usesLogarithmic, log);
      expect(after.y(marketPrice), closeTo(focalY, 1e-7));
      expect(after.price(after.y(200)), closeTo(200, 1e-8));
      expect(after.crosshairPrice(focalY),
          closeTo(marketPrice, marketPrice * 1e-9));
    });
  }

  test('inverted AUTO margins remain on physical top and bottom', () {
    final scale = ChartPriceScale.visible(candles,
        viewport, width, height, inverted: true,
        topMarginPercent: 10, bottomMarginPercent: 20);
    expect(scale.sourceMinimum, 10);
    expect(scale.sourceMaximum, 1200);
    expect(scale.y(10), closeTo(height * .1, 1e-7));
    expect(scale.y(1200), closeTo(height * .8, 1e-7));
  });

  test('LOG fallback on zero prices still inverts a linear ruler', () {
    const source = <TradeCandle>[TradeCandle(4, 20, 0, 12)];
    final scale = ChartPriceScale.visible(
        source, viewport, width, height, inverted: true, logarithmic: true);
    expect(scale.inverted, isTrue);
    expect(scale.usesLogarithmic, isFalse);
    expect(scale.y(20), greaterThan(scale.y(0)));
    expect(scale.price(scale.y(0)), closeTo(0, 1e-8));
    final positiveLog = ChartPriceScale.visible(candles,
        viewport, width, height, inverted: true, logarithmic: true);
    expect(positiveLog.y(-20).isFinite, isTrue);
    expect(positiveLog.y(-20), lessThan(0));
  });

  test('cached price transform separates inverted vs normal, linear vs LOG',
      () {
    final cache = ChartPriceScaleCache();
    ChartPriceScale resolve({bool log = false, bool invert = false}) =>
      cache.resolve(candles: candles, viewport: viewport,
        plotWidth: width, plotHeight: height,
        logarithmic: log, inverted: invert,
        topMarginPercent: 8, bottomMarginPercent: 8);
    final standard = resolve();
    final flipped = resolve(invert: true);
    expect(identical(flipped, standard), isFalse);
    expect(flipped.inverted, isTrue);
    expect(identical(resolve(invert: true), flipped), isTrue);
    final flippedLog = resolve(log: true, invert: true);
    expect(flippedLog.inverted, isTrue);
    expect(flippedLog.usesLogarithmic, isTrue);
    expect(identical(flipped, flippedLog), isFalse);
    expect(resolve(log: true).inverted, isFalse);
    expect(resolve().usesLogarithmic, isFalse);
  });

  test('inversion cannot leak future OHLC into a Replay prefix', () {
    const source = <TradeCandle>[
      TradeCandle(10, 20, 9, 15),
      TradeCandle(15, 22, 11, 16),
      TradeCandle(100, 99999, 60, 70000),
    ];
    final scale = ChartPriceScale.visible(
        CandlePrefix(source, 2), viewport, width, height,
        logarithmic: true, inverted: true);
    expect(scale.inverted, isTrue);
    expect(scale.sourceMaximum, 22);
    expect(scale.maximum, lessThan(100));
    expect(scale.sourceVisibleEnd, 2);
    expect(scale.y(20), greaterThan(scale.y(10)));
  });

  test('inverted setting persists, defaults off for existing users', () {
    const original = ChartScaleSettings();
    expect(original.inverted, isFalse);
    final changed = original.copyWith(inverted: true,
        scaleMode: 'لوغاريتمي');
    final restored = ChartScaleSettings.decode(changed.encode());
    expect(restored.inverted, isTrue);
    expect(restored.scaleMode, 'لوغاريتمي');
    expect(ChartScaleSettings.decode('{}').inverted, isFalse);
    expect(ChartScaleSettings.decode('{"inverted":"bad"}').inverted,
        isFalse);
  });
}
