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

  test('same-minute cTrader BID changes update painter, not chart header',
      () {
    final base = DateTime.utc(2026, 11, 19, 12, 3)
        .millisecondsSinceEpoch;
    final closed = DateTime.utc(2026, 11, 19, 12, 2)
        .millisecondsSinceEpoch;
    MarketQuote sample(int millisecond, double bid) => MarketQuote(
      symbol: 'XAUUSD', source: TradeSource.ctrader,
      bid: bid, ask: bid + 0.2, timestampMs: base + millisecond);
    final first = sample(1000, 3987.0);
    for (var i = 1; i <= 40; i++) {
      final updated = sample(i * 1000 + 1000, 3987 + i / 100);
      expect(ChartFeedHealth.quoteChanged(first, updated), isTrue);
      expect(ChartFeedHealth.quoteHeaderEvidenceChanged(
        previous: first, next: updated,
        lastClosedOpenMs: closed, timeframe: '1m',
        nowMs: base + 50000), isFalse,
        reason: 'Per-price source label should repaint without full rebuild');
    }
    expect(ChartFeedHealth.quoteHeaderEvidenceChanged(
      previous: first, next: sample(61000, 3987.99),
      lastClosedOpenMs: closed, timeframe: '1m',
      nowMs: base + 62000), isTrue,
      reason: 'A different verified source minute changes tooltip evidence');
  });

  test('source expiry, reconnection and mid-minute lag update header',
      () {
    final zero = DateTime.utc(2026, 11, 19, 12)
        .millisecondsSinceEpoch;
    MarketQuote sample(int offsetMs, [String symbol = 'XAUUSD']) =>
        MarketQuote(symbol: symbol, source: TradeSource.ctrader,
          bid: 4000, ask: 4000.5, timestampMs: zero + offsetMs);

    // Price quote status changes from missing to verified, then expires.
    expect(ChartFeedHealth.quoteHeaderEvidenceChanged(
      previous: null, next: sample(60000),
      lastClosedOpenMs: zero, timeframe: '1m', nowMs: zero + 60000), isTrue);
    expect(ChartFeedHealth.quoteHeaderEvidenceChanged(
      previous: sample(60000), next: null,
      lastClosedOpenMs: zero, timeframe: '1m', nowMs: zero + 120000), isTrue);
    expect(ChartFeedHealth.quoteHeaderEvidenceChanged(
      previous: sample(60000), next: sample(61000, 'EURUSD'),
      lastClosedOpenMs: zero, timeframe: '1m', nowMs: zero + 61000), isTrue);

    // Two quotes within 12:10; the first is on the healthy ten-minute
    // threshold, while the next one crosses that threshold by 1 millisecond.
    expect(ChartFeedHealth.quoteHeaderEvidenceChanged(
      previous: sample(600000), next: sample(600001),
      lastClosedOpenMs: zero, timeframe: '1m',
      nowMs: zero + 600001), isTrue,
      reason: 'Stale closed-candle badge changes even within one minute');
    expect(ChartFeedHealth.quoteHeaderEvidenceChanged(
      previous: null, next: null,
      lastClosedOpenMs: zero, timeframe: '1m', nowMs: zero), isFalse);
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

  test('read-only chart quote polling reuses fresh Markets quotes', () {
    const now = 2000000;
    expect(ChartFeedHealth.shouldRequestQuote(
      nowMs: now, lastAttemptMs: 0, freshQuoteTimestampMs: now - 15000
    ), isFalse, reason: 'A quote refreshed in Markets should not be fetched twice');
    expect(ChartFeedHealth.shouldRequestQuote(
      nowMs: now, lastAttemptMs: now - 30000
    ), isFalse, reason: 'Throttle quote source requests to one per minute');
    expect(ChartFeedHealth.shouldRequestQuote(
      nowMs: now, lastAttemptMs: now - 60000
    ), isTrue);
    expect(ChartFeedHealth.shouldRequestQuote(
      nowMs: now, lastAttemptMs: 0, freshQuoteTimestampMs: now - 61000
    ), isTrue, reason: 'An old quote is due for a new source check');
    expect(ChartFeedHealth.shouldRequestQuote(
      nowMs: now, lastAttemptMs: now + 10000
    ), isFalse, reason: 'Clock changes must not create request bursts');
  });

  test('empty initial OHLC history retries after two minutes, not each poll',
      () {
    const initialAttempt = 1000000;
    for (final seconds in [0, 30, 60, 90, 119]) {
      expect(ChartFeedHealth.shouldRetryEmptyHistory(
        nowMs: initialAttempt + seconds * 1000,
        lastAttemptMs: initialAttempt,
      ), isFalse, reason: 'No extra network call after $seconds seconds');
    }
    expect(ChartFeedHealth.shouldRetryEmptyHistory(
      nowMs: initialAttempt + 120000,
      lastAttemptMs: initialAttempt,
    ), isTrue);
    // A failed retry updates the attempt timestamp, resetting the throttle.
    expect(ChartFeedHealth.shouldRetryEmptyHistory(
      nowMs: initialAttempt + 150000,
      lastAttemptMs: initialAttempt + 120000,
    ), isFalse);
    expect(ChartFeedHealth.shouldRetryEmptyHistory(
      nowMs: initialAttempt + 240000,
      lastAttemptMs: initialAttempt + 120000,
    ), isTrue);
  });

  test('empty-history recovery rejects invalid or reversed device clock', () {
    expect(ChartFeedHealth.shouldRetryEmptyHistory(
      nowMs: 0, lastAttemptMs: 0), isFalse);
    expect(ChartFeedHealth.shouldRetryEmptyHistory(
      nowMs: 100000, lastAttemptMs: -1), isFalse);
    expect(ChartFeedHealth.shouldRetryEmptyHistory(
      nowMs: 100000, lastAttemptMs: 110000), isFalse);
    expect(ChartFeedHealth.shouldRetryEmptyHistory(
      nowMs: 500000, lastAttemptMs: 100000,
      minimumIntervalMs: 0), isFalse);
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
  test('hidden BID/ASK quotes do not repaint 120k-candle canvas on updates',
      () {
    const first = MarketQuote(
      symbol: 'XAUUSD', source: TradeSource.ctrader,
      bid: 3900, ask: 3900.2, timestampMs: 1000000);
    var repaintCount = 0;
    var previous = first;
    for (var i = 1; i <= 240; i++) {
      final latest = MarketQuote(
        symbol: 'XAUUSD', source: TradeSource.ctrader,
        bid: 3900 + i * .01, ask: 3900.2 + i * .01,
        timestampMs: 1000000 + i * 100);
      expect(ChartFeedHealth.quoteChanged(previous, latest), isTrue,
        reason: 'Real broker revisions remain recognized and archived');
      if (ChartFeedHealth.quoteAffectsChartCanvas(
          previous: previous, next: latest, bidAskLabelsVisible: false)) {
        repaintCount++;
      }
      previous = latest;
    }
    expect(repaintCount, 0,
        reason: 'A hidden quote must never invalidate candle raster on ticks');
    expect(previous.bid, closeTo(3902.4, 1e-9));
    expect(previous.timestampMs, 1024000);
  });

  test('visible BID/ASK redraws on real price/visibility, not timestamp',
      () {
    const first = MarketQuote(
      symbol: 'EURUSD', source: TradeSource.ctrader,
      bid: 1.1000, ask: 1.1002, timestampMs: 500000);
    const timestampOnly = MarketQuote(
      symbol: 'EURUSD', source: TradeSource.ctrader,
      bid: 1.1000, ask: 1.1002, timestampMs: 510000);
    const changed = MarketQuote(
      symbol: 'EURUSD', source: TradeSource.ctrader,
      bid: 1.1001, ask: 1.1003, timestampMs: 520000);
    bool paint(MarketQuote? old, MarketQuote? next, bool visible) =>
        ChartFeedHealth.quoteAffectsChartCanvas(
          previous: old, next: next, bidAskLabelsVisible: visible);
    expect(ChartFeedHealth.quoteChanged(first, timestampOnly), isTrue);
    expect(paint(first, timestampOnly, true), isFalse,
        reason: 'Quote timestamps are not painted as axis labels');
    expect(paint(first, changed, true), isTrue);
    expect(paint(first, changed, false), isFalse);
    expect(paint(null, first, true), isTrue);
    expect(paint(first, null, true), isTrue,
        reason: 'Source expiry must remove a stale visible BID/ASK label');
    expect(paint(null, null, true), isFalse);
  });

  test('hidden quote still updates candle-lag header and source minute',
      () {
    final start = DateTime.utc(2026, 11, 22, 15).millisecondsSinceEpoch;
    MarketQuote sample(int ms, double bid) => MarketQuote(
      symbol: 'XAUUSD', source: TradeSource.ctrader,
      bid: bid, ask: bid + .2, timestampMs: ms);
    final early = sample(start + 10000, 3900);
    final newMinute = sample(start + 62000, 3901);
    expect(ChartFeedHealth.quoteAffectsChartCanvas(
      previous: early, next: newMinute,
      bidAskLabelsVisible: false), isFalse);
    expect(ChartFeedHealth.quoteHeaderEvidenceChanged(
      previous: early, next: newMinute,
      lastClosedOpenMs: start, timeframe: '1m',
      nowMs: start + 62000), isTrue,
      reason: 'The separate source-evidence header must still be rebuilt');
    expect(ChartFeedHealth.quoteHeaderEvidenceChanged(
      previous: early, next: null,
      lastClosedOpenMs: start, timeframe: '1m',
      nowMs: start + 62000), isTrue,
      reason: 'Expired cTrader quote evidence must still be reported');
  });

}
