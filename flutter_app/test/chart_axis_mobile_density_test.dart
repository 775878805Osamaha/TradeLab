import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/chart/chart_axis_ticks.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('Replay-compact axes request fewer ticks than full-height chart', () {
    expect(ChartAxisTicks.intervalsForHeight(84), 3);
    expect(ChartAxisTicks.intervalsForHeight(155), 7);
    expect(ChartAxisTicks.intervalsForHeight(440), 12);
    expect(ChartAxisTicks.intervalsForHeight(1200), 12);
    expect(ChartAxisTicks.intervalsForHeight(0), 2);
    expect(ChartAxisTicks.intervalsForHeight(double.nan), 2);
    expect(ChartAxisTicks.intervalsForHeight(double.infinity), 2);
  });

  for (final inverted in <bool>[false, true]) {
    for (final logarithmic in <bool>[false, true]) {
      for (final height in <double>[84, 155, 440]) {
        test('price tick labels stay separated at ${height}dp,'
            ' inverted=$inverted LOG=$logarithmic', () {
          const source = <TradeCandle>[
            TradeCandle(100, 1200, 80, 840),
          ];
          const viewport = ChartViewport(rightMarginBars: 4);
          final scale = ChartPriceScale.visible(source, viewport,
              259, height, logarithmic: logarithmic,
              inverted: inverted);
          final interval = ChartAxisTicks.interval(
              scale.minimum, scale.maximum,
              desiredIntervals: ChartAxisTicks.intervalsForHeight(height));
          final ticks = logarithmic
              ? ChartAxisTicks.logarithmicTicks(scale.minimum, scale.maximum)
              : ChartAxisTicks.ticksWithStep(
                  scale.minimum, scale.maximum, step: interval);
          final shown = ChartAxisTicks.spacedByPixels(
              ticks, y: scale.y, plotHeight: height).toList();
          expect(shown, isNotEmpty);
          var lastY = double.nan;
          for (final tick in shown) {
            final pixelY = scale.y(tick);
            expect(pixelY, inInclusiveRange(9, height - 9));
            expect(pixelY.isFinite, isTrue);
            if (lastY.isFinite) {
              expect((pixelY - lastY).abs(), greaterThanOrEqualTo(19),
                  reason: 'No 14dp axis labels may overlap in compact Replay');
            }
            lastY = pixelY;
          }
          expect(shown.length, lessThanOrEqualTo((height / 19).ceil()));
        });
      }
    }
  }

  test('label geometry filters invalid/outside ticks and handles inversion',
      () {
    final shown = ChartAxisTicks.spacedByPixels(
        const <double>[-10, 0, 5, 10, 15, 20, 25, 30,
          double.nan, double.infinity],
        y: (value) => 100 - value * 2,
        plotHeight: 100, minLabelGap: 20).toList();
    expect(shown, <double>[5, 15, 25, 30]);
    expect(ChartAxisTicks.spacedByPixels(<double>[1, 2],
        y: (value) => double.nan, plotHeight: 100), isEmpty);
    expect(ChartAxisTicks.spacedByPixels(<double>[1, 2],
        y: (value) => value, plotHeight: 0), isEmpty);
  });

  test('Replay tick scale never reads future source prices', () {
    const candles = <TradeCandle>[
      TradeCandle(10, 15, 9, 12),
      TradeCandle(12, 18, 11, 16),
      TradeCandle(9999, 99999, 5000, 70000),
    ];
    const viewport = ChartViewport();
    final visible = CandlePrefix(candles, 2);
    final scale = ChartPriceScale.visible(visible, viewport, 259, 84,
        inverted: true, logarithmic: true);
    expect(scale.sourceMaximum, 18);
    final ticks = ChartAxisTicks.logarithmicTicks(
        scale.minimum, scale.maximum);
    final drawn = ChartAxisTicks.spacedByPixels(ticks,
        y: scale.y, plotHeight: 84).toList();
    expect(drawn.every((price) => price < 30), isTrue);
    expect(scale.sourceVisibleEnd, 2);
  });
}
