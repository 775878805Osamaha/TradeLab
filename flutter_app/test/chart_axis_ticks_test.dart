import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_axis_ticks.dart';

void main() {
  test('XAUUSD-like price ranges get legible 4-dollar marks', () {
    expect(ChartAxisTicks.interval(4020, 4072), 4);
    expect(ChartAxisTicks.ticks(4020, 4072).toList(),
        [4020, 4024, 4028, 4032, 4036, 4040, 4044,
         4048, 4052, 4056, 4060, 4064, 4068, 4072]);
    expect(ChartAxisTicks.decimals(4), 2);
  });

  test('forex and crypto prices retain appropriate precision', () {
    expect(ChartAxisTicks.interval(1.0710, 1.0770), .0005);
    expect(ChartAxisTicks.decimals(.0005), 5);
    expect(ChartAxisTicks.interval(50000, 51200), 100);
  });

  test('sub-pip forex axis labels stay distinct after manual ruler zoom', () {
    final min = 1.072100000;
    final max = 1.072100012;
    final step = ChartAxisTicks.interval(min, max);
    expect(step, closeTo(1e-9, 1e-18));
    final digits = ChartAxisTicks.decimals(step);
    expect(digits, 9,
        reason: 'Seven decimal places collapse genuine 1e-9 price ticks');
    final prices = ChartAxisTicks.ticks(min, max).toList();
    expect(prices.length, greaterThan(5));
    final labels = prices.map((p) => p.toStringAsFixed(digits)).toList();
    expect(labels.toSet().length, prices.length,
        reason: 'Every different painted y-level needs a different label');
    expect(prices.first, greaterThanOrEqualTo(min - step));
    expect(prices.last, lessThanOrEqualTo(max + step));
    expect(prices.last, greaterThan(prices.first));
    expect(prices.map((p) => p.toStringAsFixed(7)).toSet().length,
        lessThan(prices.length),
        reason: 'Prove the pre-fix axis displayed duplicate prices');
  });

  test('microprice steps get minimum required decimals, not false precision', () {
    expect(ChartAxisTicks.decimals(.0000004), 7);
    expect(ChartAxisTicks.decimals(.00000025), 8);
    expect(ChartAxisTicks.decimals(.00000005), 8);
    expect(ChartAxisTicks.decimals(.000000002), 9);
    expect(ChartAxisTicks.decimals(.0000000001), 10);
    expect(ChartAxisTicks.decimals(.000000000025), 12);
    expect(ChartAxisTicks.decimals(1e-18), 12,
        reason: 'Never claim arbitrary/unbounded device precision');
  });

  test('normal chart appearance and invalid step fallback stay unchanged', () {
    expect(ChartAxisTicks.decimals(10), 2);
    expect(ChartAxisTicks.decimals(.01), 3);
    expect(ChartAxisTicks.decimals(.0001), 5);
    expect(ChartAxisTicks.decimals(.000001), 7);
    expect(ChartAxisTicks.decimals(0), 7);
    expect(ChartAxisTicks.decimals(-3), 7);
    expect(ChartAxisTicks.decimals(double.nan), 7);
    expect(ChartAxisTicks.decimals(double.infinity), 7);
  });

  test('invalid price ranges cannot loop forever', () {
    expect(ChartAxisTicks.ticks(20, 19).toList(), isEmpty);
    expect(ChartAxisTicks.interval(20, 20), 1);
  });

  test('shared chart axis step produces identical real ticks for all markets',
      () {
    const ranges = <(double, double)>[
      (4020, 4072),
      (3900.3, 3912.8),
      (1.071, 1.077),
      (1.072100000, 1.072100012),
      (52000, 53000),
      (50000, 51200),
      (0.00001, 0.000011),
      (-250, -150),
      (-5.5, 4.5),
      (0, 2000),
      (10, 10),
      (20, 19),
    ];
    for (final (min, max) in ranges) {
      for (final wanted in [4, 8, 12, 20]) {
        final step = ChartAxisTicks.interval(
          min, max, desiredIntervals: wanted);
        final viaExisting = ChartAxisTicks.ticks(
          min, max, desiredIntervals: wanted).toList();
        final reused = ChartAxisTicks.ticksWithStep(
          min, max, step: step).toList();
        expect(reused, viaExisting,
            reason: 'Painter must preserve every legacy price tick '
                'for $min..$max at $wanted intervals');
        expect(reused.length, lessThanOrEqualTo(100),
            reason: 'Never grow the axis label array with tiny step sizes');
      }
    }
  });

  test('precomputed step honors the old 100-label guard and invalid ranges',
      () {
    expect(ChartAxisTicks.ticksWithStep(0, 2000, step: 1).toList(),
        List<double>.generate(100, (index) => index.toDouble()));
    expect(ChartAxisTicks.ticksWithStep(5, 4, step: 1), isEmpty);
    expect(ChartAxisTicks.ticksWithStep(
      double.nan, 100, step: 1), isEmpty);
    expect(ChartAxisTicks.ticksWithStep(
      0, 100, step: double.nan), isEmpty);
    expect(ChartAxisTicks.ticksWithStep(
      0, 100, step: double.infinity), isEmpty);
    expect(ChartAxisTicks.ticksWithStep(
      0, 100, step: 0), isEmpty);
    expect(ChartAxisTicks.ticksWithStep(
      0, 100, step: -1), isEmpty);
  });
}
