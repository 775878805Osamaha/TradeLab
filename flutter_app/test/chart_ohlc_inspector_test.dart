import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_ohlc_inspector.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('3px historical crosshair OHLC matches time guide source index', () {
    final candles = List<TradeCandle>.generate(100, (i) =>
        TradeCandle(100 + i.toDouble(), 104 + i.toDouble(),
            97 + i.toDouble(), 101 + i.toDouble()));
    final timestamps = List<int>.generate(100,
        (i) => DateTime.utc(2026, 11, 19).millisecondsSinceEpoch + i * 300000);
    const viewport = ChartViewport(
        barWidth: 3, scrollBars: 20, rightMarginBars: 4);
    final center = viewport.chartX(
        index: 70, candleCount: candles.length, plotWidth: 330);
    final found = ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: center + 1.1, plotWidth: 330,
      candles: candles, timestampsUtcMs: timestamps,
    );
    expect(found, isNotNull);
    expect(found!.index, 70);
    expect(found.candle.open, 170);
    expect(found.candle.high, 174);
    expect(found.candle.low, 167);
    expect(found.candle.close, 171);
    expect(found.utcTimestampMs, timestamps[70]);
    expect(found.formatPrice(found.candle.close, 2), '171.00');
    final next = ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: center + 2.0, plotWidth: 330,
      candles: candles, timestampsUtcMs: timestamps,
    );
    expect(next?.index, 71,
        reason: 'The guide, the candle and all four OHLC prices move together');
  });

  test('Replay selection is limited to visible candle prefix, not archive', () {
    const viewport = ChartViewport(barWidth: 10, scrollBars: -4);
    final wholeArchive = <TradeCandle>[
      const TradeCandle(10, 15, 9, 12),
      const TradeCandle(12, 14, 10, 11),
      const TradeCandle(11, 19, 10, 18),
      const TradeCandle(18, 22, 17, 20),
      const TradeCandle(999, 9999, 998, 9000),
    ];
    final allUtc = List<int>.generate(5,
        (i) => DateTime.utc(2026, 11, 19).millisecondsSinceEpoch + i * 60000);
    final replay = wholeArchive.sublist(0, 4);
    final lastVisibleX = viewport.chartX(
        index: 3, candleCount: replay.length, plotWidth: 300);
    final actual = ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: lastVisibleX,
      plotWidth: 300, candles: replay, timestampsUtcMs: allUtc);
    expect(actual?.index, 3);
    expect(actual?.candle.close, 20);
    expect(actual?.utcTimestampMs, allUtc[3]);
    expect(ChartOhlcInspector.atCrosshair(
      viewport: viewport, touchX: 290,
      plotWidth: 300, candles: replay, timestampsUtcMs: allUtc), isNull,
      reason: 'There is no future candle in Replay right-hand whitespace');
    expect(wholeArchive[4].close, 9000);
  });

  test('Range/HA inspected prices are the displayed representation', () {
    const raw = TradeCandle(2100, 2110, 2090, 2105);
    const heikin = TradeCandle(2102, 2109, 2092, 2104);
    const range = TradeCandle(2100, 2103, 2099, 2102);
    const viewport = ChartViewport(barWidth: 30);
    final x = viewport.chartX(index: 0, candleCount: 1, plotWidth: 300);
    const utc = [1795075200123];
    ChartOhlcSelection? inspect(TradeCandle candle) =>
        ChartOhlcInspector.atCrosshair(
          viewport: viewport, touchX: x, plotWidth: 300,
          candles: [candle], timestampsUtcMs: utc);
    expect(inspect(heikin)?.candle.close, 2104);
    expect(inspect(range)?.candle.high, 2103);
    expect(inspect(range)?.utcTimestampMs, utc[0]);
    expect(inspect(raw)?.candle.close, 2105);
    expect(inspect(range)?.changePercent, closeTo(2 / 2100 * 100, 1e-9));
  });

  test('source missing, future, invalid timestamp or blank areas have no OHLC',
      () {
    const candle = TradeCandle(0, 1, 0, 0);
    const viewport = ChartViewport(barWidth: 10, scrollBars: -10);
    final center = viewport.chartX(
      index: 0, candleCount: 1, plotWidth: 300);
    ChartOhlcSelection? at(double x, List<TradeCandle> bars,
        List<int> times) => ChartOhlcInspector.atCrosshair(
          viewport: viewport, touchX: x, plotWidth: 300,
          candles: bars, timestampsUtcMs: times);
    expect(at(center, [candle], [1795075200000])?.changePercent, isNull,
        reason: 'A zero source open must not create a synthetic percent');
    expect(at(295, [candle], [1795075200000]), isNull);
    expect(at(center, const [], const []), isNull);
    expect(at(center, [candle], const []), isNull);
    expect(at(center, [candle], [0]), isNull);
    expect(at(double.nan, [candle], [1795075200000]), isNull);
  });
}
