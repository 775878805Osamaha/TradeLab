import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_historical_time_zone.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings.dart';

void main() {
  test('Replay date label follows visible candle across New York DST', () {
    final winter = DateTime.utc(2026, 1, 15).millisecondsSinceEpoch;
    final summer = DateTime.utc(2026, 7, 15).millisecondsSinceEpoch;
    final timeline = [winter, summer];

    expect(ChartHistoricalTimeZone.labelAtVisibleBar(
      zone: ChartTimeZone.newYork,
      timestampsUtcMs: timeline,
      lastVisibleIndex: 0), 'نيويورك (UTC-5)',
      reason: 'Future summer timestamps must not influence a January replay');
    expect(ChartHistoricalTimeZone.labelAtVisibleBar(
      zone: ChartTimeZone.newYork,
      timestampsUtcMs: timeline,
      lastVisibleIndex: 1), 'نيويورك (UTC-4)');
    expect(ChartHistoricalTimeZone.labelAtVisibleBar(
      zone: ChartTimeZone.utc,
      timestampsUtcMs: timeline,
      lastVisibleIndex: 0), 'UTC');
    expect(ChartHistoricalTimeZone.labelAtVisibleBar(
      zone: ChartTimeZone.device,
      timestampsUtcMs: timeline,
      lastVisibleIndex: 1), 'توقيت الجهاز');
  });

  test('Replay timezone source refuses future or invalid market indices', () {
    final winter = DateTime.utc(2026, 1, 15).millisecondsSinceEpoch;
    expect(() => ChartHistoricalTimeZone.labelAtVisibleBar(
      zone: ChartTimeZone.newYork,
      timestampsUtcMs: [winter],
      lastVisibleIndex: 1), throwsRangeError);
    expect(() => ChartHistoricalTimeZone.labelAtVisibleBar(
      zone: ChartTimeZone.newYork,
      timestampsUtcMs: [0],
      lastVisibleIndex: 0), throwsArgumentError);
  });
}
