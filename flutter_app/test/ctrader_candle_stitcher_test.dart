import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/ctrader_candle_stitcher.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _CountedVerifiedBars extends ListBase<MarketBar> {
  _CountedVerifiedBars(this.source);
  final List<MarketBar> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) =>
      throw UnsupportedError('The verified archive is immutable');

  @override
  MarketBar operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, MarketBar value) =>
      throw UnsupportedError('The verified archive is immutable');
}

void main() {
  const one = MarketBar(1000, TradeCandle(100, 101, 99, 100.5));
  const two = MarketBar(2000, TradeCandle(100.5, 102, 100, 101));
  const three = MarketBar(3000, TradeCandle(101, 103, 100.7, 102));

  test('append only new source-verified closed cTrader candles', () {
    final existing = [one, two];
    final merged = CTraderCandleStitcher.append(
      existing, [two, three],
    );
    expect(merged.map((bar) => bar.timestamp), [1000, 2000, 3000]);
    expect(merged.last.candle.close, 102);
    expect(existing, hasLength(2));
  });

  test('never invent or fill missing broker market-close minutes', () {
    const later = MarketBar(9000, TradeCandle(102, 104, 101, 103));
    final merged = CTraderCandleStitcher.append(
      [one, two], [two, later],
    );
    expect(merged.map((bar) => bar.timestamp), [1000, 2000, 9000]);
  });

  test('reject mismatched OHLC of an already verified closed candle', () {
    const changed = MarketBar(2000, TradeCandle(100.5, 108, 100, 101));
    expect(() => CTraderCandleStitcher.append(
      [one, two], [changed, three],
    ), throwsA(isA<MarketDataException>()));
  });

  test('reject late broker backfill that would shift Replay indices', () {
    const missing = MarketBar(1500, TradeCandle(100.1, 100.8, 99.5, 100.5));
    expect(() => CTraderCandleStitcher.append(
      [one, two], [missing, two, three],
    ), throwsA(isA<MarketDataException>()));
  });

  test('reject duplicate timestamps in a provider response', () {
    expect(() => CTraderCandleStitcher.append(
      [one], [two, two],
    ), throwsA(isA<MarketDataException>()));
  });

  test('120k archive live refresh uses logarithmic overlap lookup', () {
    const firstMs = 1700000000000;
    final historical = List<MarketBar>.generate(120000, (index) =>
        MarketBar(firstMs + index * 60000, one.candle),
        growable: false);
    final measured = _CountedVerifiedBars(historical);
    final overlaps = [historical.first, historical[60000], historical.last];

    expect(CTraderCandleStitcher.countNewFromVerifiedHistory(
        measured, overlaps), 0);
    expect(measured.reads, lessThan(90),
        reason: 'Every 30-second poll must not traverse 120k closed bars');
    expect(identical(CTraderCandleStitcher.appendPreviouslyVerified(
        measured, overlaps), measured), isTrue);
    expect(measured.reads, lessThan(180),
        reason: 'Overlap-only refresh still avoids the 120k source scan');

    final future = MarketBar(historical.last.timestamp + 60000, one.candle);
    final appended = CTraderCandleStitcher.appendPreviouslyVerified(
        measured, [historical.last, future]);
    expect(appended, hasLength(120001));
    expect(appended.last, same(future));
    expect(historical, hasLength(120000));
  });

  test('trusted cTrader refresh still rejects revised and backfill OHLC', () {
    const revised = MarketBar(2000, TradeCandle(100.5, 108, 100, 101));
    const late = MarketBar(1500, TradeCandle(100, 101, 99, 100.5));
    expect(() => CTraderCandleStitcher.countNewFromVerifiedHistory(
        [one, two], [revised]), throwsA(isA<MarketDataException>()));
    expect(() => CTraderCandleStitcher.countNewFromVerifiedHistory(
        [one, two], [late]), throwsA(isA<MarketDataException>()));
    expect(CTraderCandleStitcher.appendPreviouslyVerified(
        [one, two], [two, three]), hasLength(3));
    expect(() => CTraderCandleStitcher.append(
        [two, one], [three]), throwsA(isA<MarketDataException>()),
        reason: 'Unknown direct callers must still validate full archives');
  });

  test('120k source candles append only two genuine new closes', () {
    const firstTime = 1700000000000;
    const minute = 60000;
    final historical = List<MarketBar>.generate(120000, (i) {
      final open = 1900.0 + i * .01;
      return MarketBar(firstTime + i * minute,
          TradeCandle(open, open + .6, open - .3, open + .2));
    });
    MarketBar future(int extra) {
      final open = 3100.0 + extra;
      return MarketBar(firstTime + (historical.length + extra) * minute,
          TradeCandle(open, open + .6, open - .3, open + .2));
    }
    final oneNew = future(0);
    final twoNew = future(1);
    final updated = CTraderCandleStitcher.append(historical, [
      historical[0], historical[59999], historical.last, oneNew, twoNew,
    ]);
    expect(updated, hasLength(120002));
    for (final i in [0, 1, 59999, 60000, 119998, 119999]) {
      expect(identical(updated[i], historical[i]), isTrue);
    }
    expect(updated[120000].timestamp, oneNew.timestamp);
    expect(updated.last.timestamp, twoNew.timestamp);
    expect(historical.length, 120000);
    expect(() => updated.add(oneNew), throwsUnsupportedError);
  });


  test('overlap-only refresh preserves 120k-bar list identity and no copy',
      () {
    const start = 1700000000000;
    final historical = List<MarketBar>.unmodifiable(
        List<MarketBar>.generate(120000, (index) {
      final price = 1900.0 + index * .01;
      return MarketBar(start + index * 60000,
          TradeCandle(price, price + .6, price - .3, price + .2));
    }));
    final overlapOnly = [
      historical[0], historical[60000], historical[100000], historical.last,
    ];
    final result = CTraderCandleStitcher.append(historical, overlapOnly);
    expect(identical(result, historical), isTrue,
        reason: 'No new verified bar means no 120k-entry list allocation');
    expect(result.length, 120000);
    expect(identical(result.last, historical.last), isTrue);
    expect(() => result.add(historical.last), throwsUnsupportedError);
    expect(identical(CTraderCandleStitcher.append(historical, []),
        historical), isTrue);
  });

  test('old OHLC conflict far inside long verified history fails closed', () {
    const start = 1700000000000;
    final existing = List<MarketBar>.generate(100001, (i) =>
      MarketBar(start + i * 60000,
          TradeCandle(100 + i * .01, 101 + i * .01,
              99 + i * .01, 100.5 + i * .01)));
    final sample = existing[80000];
    final changed = MarketBar(sample.timestamp,
        TradeCandle(sample.candle.open, sample.candle.high + 1,
            sample.candle.low, sample.candle.close));
    final later = MarketBar(existing.last.timestamp + 60000,
        const TradeCandle(1101, 1102, 1100, 1101.5));
    expect(() => CTraderCandleStitcher.append(existing, [
      existing[4], changed, existing.last, later,
    ]), throwsA(isA<MarketDataException>()));
    expect(existing.length, 100001);
    expect(existing[80000].candle.high, sample.candle.high);
  });

  test('never inserts broker backfill into a historical market gap', () {
    const a = MarketBar(1000, TradeCandle(100, 102, 99, 101));
    const c = MarketBar(3000, TradeCandle(101, 105, 100, 104));
    const b = MarketBar(2000, TradeCandle(101, 103, 100, 102));
    expect(() => CTraderCandleStitcher.append([a, c], [b, c]),
        throwsA(isA<MarketDataException>()));
    // The gap is a broker fact, not a candle to be inferred or inserted.
    expect(CTraderCandleStitcher.append([a, c], [c]).length, 2);
  });
}
