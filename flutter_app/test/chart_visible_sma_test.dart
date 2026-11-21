import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_visible_sma.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  List<TradeCandle> bars(Iterable<double> closes) =>
      closes.map((close) =>
          TradeCandle(close, close, close, close)).toList(growable: false);

  test('panned historical SMA label follows last visible bar, not newest',
      () {
    final candles = bars(
        List<double>.generate(30, (index) => (index + 1).toDouble()));
    // When 1..20 are visible, the plotted point uses closes 9..20.
    final historical = ChartVisibleSma.atVisibleEnd(candles, 20);
    expect(historical, closeTo(14.5, 1e-12));
    expect(ChartVisibleSma.atVisibleEnd(candles, 30),
        closeTo(24.5, 1e-12));
    expect(historical, isNot(ChartVisibleSma.atVisibleEnd(candles, 30)));

    // Panning stays anchored to the same source candles if new authentic
    // market data arrives later; the label must not jump to the future.
    final expanded = bars(
        [...List<double>.generate(30, (i) => (i + 1).toDouble()),
          9999, 7777]);
    expect(ChartVisibleSma.atVisibleEnd(expanded, 20), historical);
  });

  test('visible SMA exactly matches rolling 12-bar painter at each cutoff',
      () {
    final closes = List<double>.generate(
        53, (i) => 2000 + (i % 7) * .17 + i * .03);
    final candles = bars(closes);
    var rollingSum = 0.0;
    for (var i = 0; i < candles.length; i++) {
      rollingSum += closes[i];
      if (i >= 12) rollingSum -= closes[i - 12];
      final divisor = i < 11 ? i + 1 : 12;
      expect(ChartVisibleSma.atVisibleEnd(candles, i + 1),
          closeTo(rollingSum / divisor, 1e-9),
          reason: 'Axis label for visible end must match painted SMA point');
    }
  });

  test('Replay prefix never reads future candles and supports SMA warmup',
      () {
    final source = bars([100, 200, 300, 400, 99999, 1, 1]);
    expect(ChartVisibleSma.atVisibleEnd(source, 1), 100);
    expect(ChartVisibleSma.atVisibleEnd(source, 2), 150);
    expect(ChartVisibleSma.atVisibleEnd(source, 4), 250,
        reason: 'The hidden fifth candle cannot influence Replay SMA');
    final prefix = source.sublist(0, 4);
    expect(ChartVisibleSma.atVisibleEnd(prefix, prefix.length),
        ChartVisibleSma.atVisibleEnd(source, 4));
    expect(ChartVisibleSma.atVisibleEnd(prefix, 5), isNull);
    expect(ChartVisibleSma.atVisibleEnd(prefix, 0), isNull);
    expect(ChartVisibleSma.atVisibleEnd(const [], 1), isNull);
    expect(() => ChartVisibleSma.atVisibleEnd(source, 4, period: 0),
        throwsArgumentError);
  });

  test('different candle presentations use their own close, not raw OHLC',
      () {
    // The UI may present actual time bars, transformed Heikin Ashi, or
    // broker-BID Range bars. The axis label must use whichever is painted.
    final rawCandles = bars([100, 110, 120]);
    final displayCandles = bars([100, 103, 106]);
    expect(ChartVisibleSma.atVisibleEnd(displayCandles, 3), 103);
    expect(ChartVisibleSma.atVisibleEnd(rawCandles, 3), 110);
  });
}
