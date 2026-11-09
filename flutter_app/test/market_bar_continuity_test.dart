import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_bar_continuity.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

MarketBar bar(int timestamp) => MarketBar(timestamp,
    const TradeCandle(2000, 2002, 1999, 2001));

void main() {
  const m15 = 15 * 60000;
  final anchor = DateTime.utc(2026, 11, 9, 12).millisecondsSinceEpoch;

  test('joined verified pages retain their connected archived prefix', () {
    final provider = [bar(anchor), bar(anchor + m15)];
    final cached = [bar(anchor - 2 * m15), bar(anchor - m15)];
    final combined = MarketBarContinuity.joinLatest(
      cached: cached, provider: provider, timeframe: '15m');
    expect(combined.map((b) => b.timestamp), [
      anchor - 2 * m15, anchor - m15, anchor, anchor + m15,
    ]);
  });

  test('stale archive never disguises a missing provider interval', () {
    final provider = [bar(anchor), bar(anchor + m15)];
    final lastCached = anchor - 40 * m15;
    final combined = MarketBarContinuity.joinLatest(
      cached: [bar(lastCached - m15), bar(lastCached)],
      provider: provider, timeframe: '15m');
    expect(combined.map((b) => b.timestamp), [anchor, anchor + m15]);
    expect(MarketBarContinuity.cachedPredecessors(
      cached: [bar(lastCached)], nextOpenMs: anchor,
      timeframe: '15m'), isEmpty);
  });

  test('cache with internal missing interval exposes only its adjacent tail',
      () {
    final prefix = anchor - 20 * m15;
    final cached = [bar(prefix), bar(anchor - 2 * m15), bar(anchor - m15)];
    final connected = MarketBarContinuity.cachedPredecessors(
      cached: cached, nextOpenMs: anchor, timeframe: '15m');
    expect(connected.map((b) => b.timestamp),
      [anchor - 2 * m15, anchor - m15]);
  });

  test('calendar-month continuity uses UTC month boundaries', () {
    final october = DateTime.utc(2026, 10).millisecondsSinceEpoch;
    final november = DateTime.utc(2026, 11).millisecondsSinceEpoch;
    final january = DateTime.utc(2027).millisecondsSinceEpoch;
    expect(MarketBarContinuity.cachedPredecessors(
      cached: [bar(october)], nextOpenMs: november,
      timeframe: '1M').single.timestamp, october);
    expect(MarketBarContinuity.cachedPredecessors(
      cached: [bar(october)], nextOpenMs: january,
      timeframe: '1M'), isEmpty);
  });
}
