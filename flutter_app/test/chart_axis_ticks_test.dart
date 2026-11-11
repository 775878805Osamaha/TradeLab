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

  test('invalid price ranges cannot loop forever', () {
    expect(ChartAxisTicks.ticks(20, 19).toList(), isEmpty);
    expect(ChartAxisTicks.interval(20, 20), 1);
  });
}
