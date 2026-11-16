import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings.dart';
import 'package:tradelab_flutter/replay/replay_date_time_resolver.dart';

void main() {
  test('New York replay date resolves winter and summer UTC correctly', () {
    expect(ReplayDateTimeResolver.utcCandidates(
      zone: ChartTimeZone.newYork,
      year: 2026, month: 1, day: 15, hour: 9, minute: 45,
    ), [DateTime.utc(2026, 1, 15, 14, 45).millisecondsSinceEpoch]);
    expect(ReplayDateTimeResolver.utcCandidates(
      zone: ChartTimeZone.newYork,
      year: 2026, month: 7, day: 15, hour: 9, minute: 45,
    ), [DateTime.utc(2026, 7, 15, 13, 45).millisecondsSinceEpoch]);
  });

  test('spring-forward missing time is rejected rather than fabricated', () {
    expect(ReplayDateTimeResolver.utcCandidates(
      zone: ChartTimeZone.newYork,
      year: 2026, month: 3, day: 8, hour: 2, minute: 30,
    ), isEmpty);
    expect(ReplayDateTimeResolver.utcCandidates(
      zone: ChartTimeZone.newYork,
      year: 2026, month: 2, day: 30, hour: 9, minute: 0,
    ), isEmpty);
  });

  test('fall-back ambiguous clock time returns BOTH chronological instants', () {
    final candidates = ReplayDateTimeResolver.utcCandidates(
      zone: ChartTimeZone.newYork,
      year: 2026, month: 11, day: 1, hour: 1, minute: 30,
    );
    expect(candidates, [
      DateTime.utc(2026, 11, 1, 5, 30).millisecondsSinceEpoch,
      DateTime.utc(2026, 11, 1, 6, 30).millisecondsSinceEpoch,
    ]);
    for (final instant in candidates) {
      final visible = ReplayDateTimeResolver.displayWallTime(
          ChartTimeZone.newYork, instant);
      expect([visible.year, visible.month, visible.day,
          visible.hour, visible.minute], [2026, 11, 1, 1, 30]);
    }
  });

  test('UTC and device mode use selected timezone, not chart default', () {
    final instant = DateTime.utc(2026, 11, 1, 1, 30).millisecondsSinceEpoch;
    expect(ReplayDateTimeResolver.utcCandidates(
      zone: ChartTimeZone.utc,
      year: 2026, month: 11, day: 1, hour: 1, minute: 30,
    ), [instant]);

    final local = DateTime(2026, 11, 1, 1, 30);
    expect(ReplayDateTimeResolver.utcCandidates(
      zone: ChartTimeZone.device,
      year: 2026, month: 11, day: 1, hour: 1, minute: 30,
    ), [local.toUtc().millisecondsSinceEpoch]);
  });
}
