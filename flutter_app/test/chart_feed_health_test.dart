import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_feed_health.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  const minuteMs = Duration.millisecondsPerMinute;

  test('source quote revisions redraw only when broker evidence changes', () {
    const first = MarketQuote(
      symbol: 'XAUUSD', source: TradeSource.ctrader,
      bid: 3880, ask: 3880.2, timestampMs: 1000000,
    );
    const identical = MarketQuote(
      symbol: 'XAUUSD', source: TradeSource.ctrader,
      bid: 3880, ask: 3880.2, timestampMs: 1000000,
    );
    const newer = MarketQuote(
      symbol: 'XAUUSD', source: TradeSource.ctrader,
      bid: 3881, ask: 3881.2, timestampMs: 1001000,
    );
    expect(ChartFeedHealth.quoteChanged(null, null), isFalse);
    expect(ChartFeedHealth.quoteChanged(null, first), isTrue);
    expect(ChartFeedHealth.quoteChanged(first, identical), isFalse);
    expect(ChartFeedHealth.quoteChanged(first, newer), isTrue);
    expect(ChartFeedHealth.quoteChanged(first, null), isTrue,
      reason: 'Expired quote labels must be removed');
  });

  test('current forming minute alone is not a missing closed candle', () {
    final now = DateTime.utc(2026, 11, 16, 12, 3).millisecondsSinceEpoch;
    final lastClosed = DateTime.utc(2026, 11, 16, 12, 2)
        .millisecondsSinceEpoch;
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: lastClosed, timeframe: '1m',
      nowMs: now, freshQuoteTimestampMs: now), isFalse);
  });

  test('quote much newer than last broker-closed candle is flagged', () {
    final latest = DateTime.utc(2026, 11, 16, 12, 0)
        .millisecondsSinceEpoch;
    final freshQuote = latest + 18 * minuteMs;
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: latest, timeframe: '1m',
      nowMs: freshQuote, freshQuoteTimestampMs: freshQuote), isTrue);
  });

  test('different timeframe thresholds avoid false positive', () {
    final latest = DateTime.utc(2026, 11, 16, 12).millisecondsSinceEpoch;
    final now = latest + 18 * minuteMs;
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: latest, timeframe: '15m',
      nowMs: now, freshQuoteTimestampMs: now), isFalse);
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: latest, timeframe: '1m', nowMs: now), isTrue);
  });

  test('calendar frames keep conservative broker-offset thresholds', () {
    final last = DateTime.utc(2026, 11, 13, 22).millisecondsSinceEpoch;
    final monday = DateTime.utc(2026, 11, 16, 12).millisecondsSinceEpoch;
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: last, timeframe: '1W',
      nowMs: monday, freshQuoteTimestampMs: monday), isFalse);
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: last, timeframe: '1D',
      nowMs: monday, freshQuoteTimestampMs: monday), isFalse);
  });

  test('no evidence, invalid dates or unknown frames never claim lag', () {
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: null, timeframe: '1m', nowMs: 1000), isFalse);
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: -1, timeframe: '1m', nowMs: 1000), isFalse);
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: 1000, timeframe: 'future', nowMs: 20000000),
        isFalse);
    expect(ChartFeedHealth.closedCandlesLagging(
      latestClosedOpenMs: 200000, timeframe: '1m', nowMs: 1000), isFalse);
  });
}
