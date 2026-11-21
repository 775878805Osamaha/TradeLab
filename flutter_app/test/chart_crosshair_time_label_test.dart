import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_crosshair_time_label.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings.dart';
import 'package:tradelab_flutter/chart/chart_text_layout_cache.dart';

void main() {
  test('BID Range labels preserve source UTC seconds and milliseconds', () {
    final utc = DateTime.utc(2026, 11, 19, 2, 30, 45, 123)
        .millisecondsSinceEpoch;
    expect(ChartCrosshairTimeLabel.fromSource(
        utcTimestampMs: utc, zone: ChartTimeZone.utc,
        rangeMode: true), '19/11 02:30:45.123');
    expect(ChartCrosshairTimeLabel.fromSource(
        utcTimestampMs: utc, zone: ChartTimeZone.utc,
        rangeMode: false), '19/11 02:30');
    expect(ChartCrosshairTimeLabel.fromSource(
        utcTimestampMs: utc, zone: ChartTimeZone.newYork,
        rangeMode: true), '18/11 21:30:45.123');
  });

  test('Range bars inside one minute/second remain distinguishable', () {
    final first = DateTime.utc(2026, 11, 19, 12, 1, 2, 3)
        .millisecondsSinceEpoch;
    final second = first + 997;
    final third = first + 1;
    String label(int utc) => ChartCrosshairTimeLabel.fromSource(
      utcTimestampMs: utc, zone: ChartTimeZone.utc, rangeMode: true);
    expect(label(first), '19/11 12:01:02.003');
    expect(label(second), '19/11 12:01:03.000');
    expect(label(third), '19/11 12:01:02.004');
    expect(label(first), isNot(label(second)));
    expect(label(first), isNot(label(third)));
    // Repeated timestamps are honestly repeated; no fake millisecond or
    // ordinal is appended when two broker events share the same instant.
    expect(label(first), label(first));
  });

  test('New York display labels follow DST with no device conversion', () {
    final summer = DateTime.utc(2026, 7, 15, 2, 30, 45, 999)
        .millisecondsSinceEpoch;
    expect(ChartCrosshairTimeLabel.fromSource(
        utcTimestampMs: summer, zone: ChartTimeZone.newYork,
        rangeMode: true), '14/07 22:30:45.999');
    final winter = DateTime.utc(2026, 1, 15, 2, 30, 45, 1)
        .millisecondsSinceEpoch;
    expect(ChartCrosshairTimeLabel.fromSource(
        utcTimestampMs: winter, zone: ChartTimeZone.newYork,
        rangeMode: true), '14/01 21:30:45.001');
  });

  testWidgets('measured millisecond badge fits 320dp plot without clipping',
      (tester) async {
    final cache = ChartTextLayoutCache();
    addTearDown(cache.clear);
    const text = '19/11 02:30:45.123';
    final measured = cache.layout(text, Colors.white, 9).width;
    expect(measured, greaterThan(0));
    final width = ChartCrosshairTimeLabel.badgeWidth(
        measuredTextWidth: measured, plotWidth: 259);
    expect(width, greaterThanOrEqualTo(measured + 10));
    expect(width, lessThanOrEqualTo(259));
    expect(ChartCrosshairTimeLabel.badgeWidth(
        measuredTextWidth: measured, plotWidth: 90), 90,
        reason: 'In extremely narrow chart panes the tag clips to the plot');
    expect(ChartCrosshairTimeLabel.badgeWidth(
        measuredTextWidth: double.nan, plotWidth: 259), 0);
    expect(ChartCrosshairTimeLabel.badgeWidth(
        measuredTextWidth: measured, plotWidth: 0), 0);
    expect(() => ChartCrosshairTimeLabel.fromSource(
        utcTimestampMs: 0, zone: ChartTimeZone.utc,
        rangeMode: true), throwsArgumentError);
  });
}
