import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/ctrader_closed_bar_cutoff.dart';

void main() {
  test('intraday cutoff excludes the current open candle', () {
    final now = DateTime.utc(2026, 11, 15, 12, 37, 25);
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs('1m', now),
        DateTime.utc(2026, 11, 15, 12, 37).millisecondsSinceEpoch - 1);
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs('15m', now),
        DateTime.utc(2026, 11, 15, 12, 30).millisecondsSinceEpoch - 1);
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs('4h', now),
        DateTime.utc(2026, 11, 15, 12).millisecondsSinceEpoch - 1);
  });

  test('daily candle stays hidden until next UTC midnight', () {
    final now = DateTime.utc(2026, 11, 15, 23, 59, 59);
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs('1D', now),
        DateTime.utc(2026, 11, 15).millisecondsSinceEpoch - 1);
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs(
        '1D', DateTime.utc(2026, 11, 16)),
        DateTime.utc(2026, 11, 16).millisecondsSinceEpoch - 1);
  });

  test('weekly cutoff starts Monday UTC and survives year change', () {
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs(
        '1W', DateTime.utc(2026, 11, 15, 20)),
        DateTime.utc(2026, 11, 9).millisecondsSinceEpoch - 1);
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs(
        '1W', DateTime.utc(2027, 1, 1, 12)),
        DateTime.utc(2026, 12, 28).millisecondsSinceEpoch - 1);
  });

  test('monthly cutoff excludes the entire active UTC month', () {
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs(
        '1M', DateTime.utc(2026, 11, 30, 23, 59)),
        DateTime.utc(2026, 11).millisecondsSinceEpoch - 1);
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs(
        '1M', DateTime.utc(2027, 1, 1)),
        DateTime.utc(2027, 1).millisecondsSinceEpoch - 1);
  });

  test('offset timestamps are normalized to UTC', () {
    final offsetDate = DateTime.parse('2026-11-16T01:10:00+03:00');
    expect(CTraderClosedBarCutoff.latestAllowedOpenMs('1D', offsetDate),
        DateTime.utc(2026, 11, 15).millisecondsSinceEpoch - 1);
  });

  test('unsupported timeframes fail closed', () {
    expect(() => CTraderClosedBarCutoff.latestAllowedOpenMs(
        'invalid', DateTime.utc(2026)), throwsArgumentError);
  });
}
