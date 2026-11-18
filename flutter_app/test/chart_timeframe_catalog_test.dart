import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/chart_timeframe_catalog.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('cTrader native M2 is selectable without OHLC aggregation', () {
    expect(ChartTimeframeCatalog.forSource(TradeSource.ctrader),
        contains('2m'));
    expect(ChartTimeframeCatalog.isSupported(
        TradeSource.ctrader, '2m'), isTrue);
    expect(ChartTimeframeCatalog.isSupported(
        TradeSource.ctrader, '2h'), isFalse);
  });

  test('Binance 2h is selectable but unsupported 2m is not', () {
    expect(ChartTimeframeCatalog.forSource(TradeSource.binance),
        contains('2h'));
    expect(ChartTimeframeCatalog.isSupported(
        TradeSource.binance, '2m'), isFalse);
  });

  test('provider switch never silently submits incompatible 2m or 2h', () {
    expect(ChartTimeframeCatalog.compatibleOnSwitch(
        TradeSource.binance, '2m'), '1m');
    expect(ChartTimeframeCatalog.compatibleOnSwitch(
        TradeSource.ctrader, '2h'), '1h');
    expect(ChartTimeframeCatalog.compatibleOnSwitch(
        TradeSource.ctrader, '2m'), '2m');
    expect(ChartTimeframeCatalog.compatibleOnSwitch(
        TradeSource.binance, '2h'), '2h');
  });

  test('all existing common intervals remain selectable by both providers', () {
    for (final value in [
      '1m', '3m', '5m', '15m', '30m',
      '1h', '4h', '1D', '1W', '1M',
    ]) {
      expect(ChartTimeframeCatalog.isSupported(
          TradeSource.ctrader, value), isTrue);
      expect(ChartTimeframeCatalog.isSupported(
          TradeSource.binance, value), isTrue);
    }
  });
  test('all native timeframes have consistent Arabic chart/Replay labels', () {
    final frames = {
      ...ChartTimeframeCatalog.ctrader,
      ...ChartTimeframeCatalog.binance,
    };
    for (final timeframe in frames) {
      final localized = ChartTimeframeCatalog.displayLabel(timeframe);
      expect(localized, isNot(timeframe));
      expect(localized, isNotEmpty);
    }
    expect(ChartTimeframeCatalog.displayLabel('2m'), '2 دق');
    expect(ChartTimeframeCatalog.displayLabel('2h'), 'ساعتان');
    expect(ChartTimeframeCatalog.displayLabel('1W'), 'أسبوعي');
  });

  test('Arabic display labels never replace broker-native interval codes', () {
    for (final timeframe in ChartTimeframeCatalog.ctrader) {
      expect(ChartTimeframeCatalog.compatibleOnSwitch(
          TradeSource.ctrader, timeframe), timeframe);
    }
    for (final timeframe in ChartTimeframeCatalog.binance) {
      expect(ChartTimeframeCatalog.compatibleOnSwitch(
          TradeSource.binance, timeframe), timeframe);
    }
    expect(ChartTimeframeCatalog.displayLabel('not-an-interval'),
        'not-an-interval');
  });
}
