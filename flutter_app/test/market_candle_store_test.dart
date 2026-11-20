import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_candle_store.dart';
import 'package:tradelab_flutter/data/market_history_budget.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final gold = tradeSymbols.firstWhere((s) => s.code == 'XAUUSD');
  final btc = tradeSymbols.firstWhere((s) => s.code == 'BTCUSDT');

  test('broker account identity cannot be omitted or mixed', () {
    expect(() => MarketCandleStore.key(gold, '1m', null), throwsArgumentError);
    expect(MarketCandleStore.key(gold, '1m', 'one'),
        isNot(MarketCandleStore.key(gold, '1m', 'two')));
    expect(MarketCandleStore.key(btc, '1m', null), contains('binance'));
    // Old calendar records may contain a forming broker-offset bar from
    // the previous preview. They are never used under closed-bar policy v2.
    for (final frame in const ['1D', '1W', '1M']) {
      expect(MarketCandleStore.key(gold, frame, 'one'),
          endsWith(':broker-closed-v2'));
    }
    expect(MarketCandleStore.key(gold, '1m', 'one'),
        isNot(contains('broker-closed-v2')));
    expect(MarketCandleStore.key(btc, '1D', null),
        isNot(contains('broker-closed-v2')));
  });

  test('off-isolate SQLite decode restores 5201 genuine OHLC without gaps',
      () async {
    final account = 'large-cache-${DateTime.now().microsecondsSinceEpoch}';
    const start = 1701000000000;
    final bars = List<MarketBar>.generate(5201, (i) {
      // Keep a genuine empty one-minute interval between bars 100 and 101.
      final timestamp = start + (i + (i > 100 ? 1 : 0)) * 60000;
      final open = 1900.0 + i * .01;
      return MarketBar(timestamp,
          TradeCandle(open, open + .5, open - .4, open + .2));
    });
    expect(MarketCandleDecodePolicy.shouldOffload(4999), isFalse);
    // The large result must be parsed and verified outside the UI isolate.
    expect(MarketCandleDecodePolicy.shouldOffload(bars.length), isTrue);
    await MarketCandleStore.archive(gold, '1m', account, bars);
    final restored = await MarketCandleStore.read(gold, '1m', account);
    expect(restored.length, bars.length);
    expect(restored[101].timestamp - restored[100].timestamp, 120000);
    for (final index in [0, 100, 101, 499, 500, 4999, 5000, 5200]) {
      expect(restored[index].timestamp, bars[index].timestamp);
      expect(restored[index].candle.open, bars[index].candle.open);
      expect(restored[index].candle.high, bars[index].candle.high);
      expect(restored[index].candle.low, bars[index].candle.low);
      expect(restored[index].candle.close, bars[index].candle.close);
    }
    final mostRecent = await MarketCandleStore.read(
        gold, '1m', account, limit: 100);
    expect(mostRecent, hasLength(100));
    expect(mostRecent.first.timestamp, bars[5101].timestamp);
    expect(mostRecent.last.timestamp, bars.last.timestamp);
    expect(await MarketCandleStore.read(gold, '1m', '$account-other'),
        isEmpty);
  });

  test('startup restores 4000 recent source candles, then local older page',
      () async {
    final account = 'startup-${DateTime.now().microsecondsSinceEpoch}';
    const first = 1700000000000;
    final archive = List<MarketBar>.generate(4200, (i) {
      final time = first + (i + (i >= 3100 ? 1 : 0)) * 60000;
      final price = 4000.0 + i * .01;
      return MarketBar(time,
          TradeCandle(price, price + .5, price - .4, price + .1));
    });
    await MarketCandleStore.archive(gold, '1m', account, archive);
    final shown = await MarketCandleStore.read(gold, '1m', account,
        limit: MarketCandleStore.initialChartPageSize);
    expect(shown, hasLength(4000));
    expect(shown.first.timestamp, archive[200].timestamp);
    final older = await MarketCandleStore.readOlder(
        gold, '1m', account, beforeMs: shown.first.timestamp);
    expect(older, hasLength(200));
    expect(older.first.timestamp, archive.first.timestamp);
    expect(older.last.timestamp, archive[199].timestamp);
    final full = [...older, ...shown];
    expect(full.map((b) => b.timestamp),
        archive.map((b) => b.timestamp));
    expect(full[3100].timestamp - full[3099].timestamp, 120000,
        reason: 'Never fabricate a missing verified broker minute');
  });

  test('local older pages are account-isolated and strictly before cursor',
      () async {
    final account = 'older-${DateTime.now().microsecondsSinceEpoch}';
    const start = 1702000000000;
    final archive = List<MarketBar>.generate(1602, (i) {
      final price = 1900.0 + i * .01;
      return MarketBar(start + i * 60000,
          TradeCandle(price, price + .5, price - .3, price + .1));
    });
    await MarketCandleStore.archive(gold, '1m', account, archive);
    final recent = await MarketCandleStore.read(gold, '1m', account,
        limit: 100);
    final page1 = await MarketCandleStore.readOlder(
        gold, '1m', account, beforeMs: recent.first.timestamp, limit: 600);
    final page2 = await MarketCandleStore.readOlder(
        gold, '1m', account, beforeMs: page1.first.timestamp, limit: 600);
    expect(page1, hasLength(600));
    expect(page2, hasLength(600));
    expect(page1.last.timestamp, lessThan(recent.first.timestamp));
    expect(page2.last.timestamp, lessThan(page1.first.timestamp));
    expect(page2.first.timestamp, archive[302].timestamp);
    expect(await MarketCandleStore.readOlder(
        gold, '1m', 'another-account', beforeMs: recent.first.timestamp),
        isEmpty);
    expect(await MarketCandleStore.readOlder(
        btc, '1m', null, beforeMs: recent.first.timestamp), isEmpty);
    expect(await MarketCandleStore.readOlder(
        gold, '1m', account, beforeMs: archive.first.timestamp), isEmpty);
    for (final (time, size) in <(int, int)>[
      (0, 10), (-1, 10), (start, 0), (start, 200001),
    ]) {
      await expectLater(MarketCandleStore.readOlder(
        gold, '1m', account, beforeMs: time, limit: size),
        throwsArgumentError);
    }
  });

  test('older page respects remaining 200k chart-memory budget', () {
    expect(MarketCandleStore.olderPageCapacity(0), 2000);
    expect(MarketCandleStore.olderPageCapacity(198000), 2000);
    expect(MarketCandleStore.olderPageCapacity(199999), 1);
    expect(MarketCandleStore.olderPageCapacity(200000), 0);
    expect(() => MarketCandleStore.olderPageCapacity(-1),
        throwsArgumentError);
    expect(() => MarketCandleStore.olderPageCapacity(200001),
        throwsArgumentError);
  });

  test('older cached islands cannot skip periods that were never archived',
      () {
    const minute = 60000;
    const t = 1700000000000;
    const candle = TradeCandle(100, 101, 99, 100.5);
    final cached = [
      for (var i in [0, 1, 2, 40, 41, 42])
        MarketBar(t + i * minute, candle),
    ];
    final suffix = MarketCandleStore.contiguousOlderPage(
      source: cached, beforeMs: t + 43 * minute, timeframe: '1m');
    expect(suffix.map((bar) => bar.timestamp), [
      t + 40 * minute, t + 41 * minute, t + 42 * minute,
    ]);
    final unverifiedGap = MarketCandleStore.contiguousOlderPage(
      source: cached.take(3).toList(growable: false),
      beforeMs: t + 40 * minute, timeframe: '1m');
    expect(unverifiedGap, isEmpty,
        reason: 'Do not skip actual possible cTrader candles 3..39');
    expect(cached, hasLength(6));
  });

  test('full continuous local page preserves original source list identity',
      () {
    const t = 1700000000000;
    const candle = TradeCandle(100, 101, 99, 100.5);
    final page = List<MarketBar>.generate(2000,
        (i) => MarketBar(t + i * 60000, candle), growable: false);
    final selected = MarketCandleStore.contiguousOlderPage(
      source: page, beforeMs: t + page.length * 60000,
      timeframe: '1m');
    expect(selected, same(page),
        reason: 'Avoid another 2000-object page copy for chart gestures');
    expect(selected, hasLength(2000));
    expect(MarketCandleStore.contiguousOlderPage(
      source: page, beforeMs: t + (page.length + 5) * 60000,
      timeframe: '1m'), isEmpty);
  });

  test('market closures and variable calendar months require broker coverage',
      () {
    const t = 1700000000000;
    const candle = TradeCandle(100, 101, 99, 100.5);
    final page = [const MarketBar(t, candle)];
    expect(MarketCandleStore.contiguousOlderPage(
      source: page, beforeMs: t + 3 * 86400000,
      timeframe: '1D'), isEmpty);
    expect(MarketCandleStore.contiguousOlderPage(
      source: page, beforeMs: t + 31 * 86400000,
      timeframe: '1M'), isEmpty);
    expect(() => MarketCandleStore.contiguousOlderPage(
      source: page, beforeMs: t, timeframe: '1m'),
      throwsA(isA<MarketDataException>()));
    expect(() => MarketCandleStore.contiguousOlderPage(
      source: page, beforeMs: 0, timeframe: '1m'),
      throwsArgumentError);
    expect(() => MarketCandleStore.contiguousOlderPage(
      source: [MarketBar(t + 60000, candle), MarketBar(t, candle)],
      beforeMs: t + 120000, timeframe: '1m'),
      throwsA(isA<MarketDataException>()));
  });

  test('persist 120 verified market candles; no fabricated gaps', () async {
    final account = 'cache-test-${DateTime.now().microsecondsSinceEpoch}';
    final bars = List<MarketBar>.generate(120, (i) {
      final price = 4000.0 + i * .5;
      return MarketBar(1700000000000 + i * 60000,
          TradeCandle(price, price + .6, price - .2, price + .1));
    });
    await MarketCandleStore.archive(gold, '1m', account, bars,
        markFresh: true);
    expect(await MarketCandleStore.isFresh(gold, '1m', account), isTrue);
    final loaded = await MarketCandleStore.read(gold, '1m', account);
    expect(loaded.length, 120);
    expect(loaded.first.timestamp, bars.first.timestamp);
    expect(loaded.last.candle.close, bars.last.candle.close);
    expect(await MarketCandleStore.read(gold, '1m', 'another-account'), isEmpty);

    // A second broker page leaves a missing minute missing, rather than
    // painting a plausible but invented OHLC gap filler.
    final appended = MarketBar(bars.last.timestamp + 120000,
        const TradeCandle(4059, 4060, 4058, 4059.5));
    await MarketCandleStore.archive(gold, '1m', account, [appended]);
    final after = await MarketCandleStore.read(gold, '1m', account);
    expect(after.length, 121);
    expect(after.last.timestamp - after[119].timestamp, 120000);
  });

  test('reject invalid OHLC before disk write', () async {
    final invalid = [const MarketBar(1234, TradeCandle(5, 4, 6, 4))];
    await expectLater(
      MarketCandleStore.archive(gold, '1m', 'bad-test', invalid),
      throwsA(isA<MarketDataException>()),
    );
  });

  test('identical broker overlap preserves verified history and gaps', () {
    const earlier = [
      MarketBar(1000, TradeCandle(10, 12, 9, 11)),
      MarketBar(3000, TradeCandle(11, 13, 10, 12)),
    ];
    const newer = [
      MarketBar(3000, TradeCandle(11, 13, 10, 12)),
      MarketBar(4000, TradeCandle(13, 15, 12, 14)),
    ];
    final merged = MarketCandleStore.mergeVerified(earlier, newer);
    expect(merged.map((bar) => bar.timestamp), [1000, 3000, 4000]);
    expect(merged[1].candle.close, 12);
    expect(() => merged.add(newer.last), throwsUnsupportedError);
  });

  test('reject broker revisions of an archived closed candle', () {
    const earlier = [
      MarketBar(1000, TradeCandle(10, 12, 9, 11)),
      MarketBar(3000, TradeCandle(11, 13, 10, 12)),
    ];
    const conflicting = [
      MarketBar(3000, TradeCandle(12, 14, 11, 13)),
      MarketBar(4000, TradeCandle(13, 15, 12, 14)),
    ];
    expect(
      () => MarketCandleStore.mergeVerified(earlier, conflicting),
      throwsA(isA<MarketDataException>()),
    );
    // A rejected refresh never mutates the previously authenticated history.
    expect(earlier.last.candle.close, 12);
  });

  test('verified merge has a positive cap and retains newest timestamps', () {
    const old = [MarketBar(1000, TradeCandle(10, 11, 9, 10))];
    const recent = [
      MarketBar(2000, TradeCandle(11, 12, 10, 11)),
      MarketBar(3000, TradeCandle(12, 13, 11, 12)),
    ];
    expect(() => MarketCandleStore.mergeVerified(old, recent, maxCount: 0),
        throwsArgumentError);
    final limited = MarketCandleStore.mergeVerified(old, recent, maxCount: 2);
    expect(limited.map((bar) => bar.timestamp), [2000, 3000]);
  });
  test('120001 provider candles remain available beyond old 100k default', () {
    const start = 1700000000000;
    final original = List<MarketBar>.generate(120001, (i) =>
        MarketBar(start + i * 60000,
            const TradeCandle(100, 101, 99, 100.5)), growable: false);
    expect(MarketHistoryBudget.maxVisibleTimeCandles, 200000);
    final visible = MarketCandleStore.mergeVerified(
        original, const <MarketBar>[]);
    expect(visible, hasLength(120001));
    expect(visible.first.timestamp, start);
    expect(visible.last.timestamp, original.last.timestamp);
    expect(original, hasLength(120001));
  });

  test('oversized on-screen SQLite read and merge limits fail closed',
      () async {
    for (final count in [0, -1, 200001]) {
      await expectLater(
        MarketCandleStore.read(gold, '1m', 'budget-check', limit: count),
        throwsArgumentError);
      expect(() => MarketCandleStore.mergeVerified(
        const <MarketBar>[], const <MarketBar>[], maxCount: count),
        throwsArgumentError);
    }
  });

  test('SQLite archive is idempotent and never overwrites broker OHLC', () async {
    final account = 'integrity-${DateTime.now().microsecondsSinceEpoch}';
    const start = 1700000000000;
    const initial = [
      MarketBar(start, TradeCandle(10, 12, 9, 11)),
      MarketBar(start + 180000, TradeCandle(13, 15, 12, 14)),
    ];
    await MarketCandleStore.archive(gold, '1m', account, initial);
    await MarketCandleStore.archive(gold, '1m', account, initial);

    const newAndConflicting = [
      MarketBar(start + 60000, TradeCandle(11, 13, 10, 12)),
      MarketBar(start + 180000, TradeCandle(13, 16, 12, 15)),
    ];
    await expectLater(
      MarketCandleStore.archive(gold, '1m', account, newAndConflicting),
      throwsA(isA<MarketDataException>()),
    );

    final after = await MarketCandleStore.read(gold, '1m', account);
    expect(after.length, 2);
    expect(after.map((bar) => bar.timestamp), [
      start, start + 180000,
    ]);
    expect(after.last.candle.high, 15);
    expect(after.last.candle.close, 14);
  });

  test('archive 1602 broker candles across indexed page boundaries without filling gaps',
      () async {
    final account = 'long-history-${DateTime.now().microsecondsSinceEpoch}';
    const firstMs = 1700000000000;
    final bars = List<MarketBar>.generate(1602, (i) {
      // One genuine missing minute survives import and an identical replay.
      final time = firstMs + (i + (i >= 701 ? 1 : 0)) * 60000;
      final price = 4000.0 + i * 0.01;
      return MarketBar(time,
          TradeCandle(price, price + .5, price - .5, price + .1));
    });
    await MarketCandleStore.archive(gold, '1m', account, bars,
        markFresh: true);
    await MarketCandleStore.archive(gold, '1m', account, bars);
    final restored = await MarketCandleStore.read(gold, '1m', account);
    expect(restored, hasLength(1602));
    expect(restored.first.timestamp, bars.first.timestamp);
    expect(restored.last.timestamp, bars.last.timestamp);
    expect(restored[701].timestamp - restored[700].timestamp, 120000);
    for (final i in [0, 499, 500, 999, 1000, 1499, 1500, 1601]) {
      expect(restored[i].timestamp, bars[i].timestamp);
      expect(restored[i].candle.open, bars[i].candle.open);
      expect(restored[i].candle.close, bars[i].candle.close);
    }
    expect(await MarketCandleStore.isFresh(gold, '1m', account), isTrue);
  });

  test('linear merge keeps 12000 authenticated bars ordered without gap filling',
      () {
    const start = 1700000000000;
    const minute = 60000;
    final existing = List<MarketBar>.generate(8000, (index) {
      final timestamp = start + (index + (index >= 2000 ? 1 : 0)) * minute;
      final price = 2000.0 + index * .01;
      return MarketBar(timestamp,
          TradeCandle(price, price + 1, price - 1, price + .5));
    });
    final incoming = List<MarketBar>.generate(4000, (index) {
      final timestamp = start + (8001 + index) * minute;
      final price = 3000.0 + index * .01;
      return MarketBar(timestamp,
          TradeCandle(price, price + 1, price - 1, price + .5));
    });
    final merged = MarketCandleStore.mergeVerified(existing, incoming);
    expect(merged, hasLength(12000));
    expect(merged.first.timestamp, existing.first.timestamp);
    expect(merged[1999].timestamp + 2 * minute, merged[2000].timestamp);
    expect(merged[8000].timestamp, incoming.first.timestamp);
    expect(merged.last.timestamp, incoming.last.timestamp);
    expect(() => merged.clear(), throwsUnsupportedError);
    final clipped = MarketCandleStore.mergeVerified(
        existing, incoming, maxCount: 10000);
    expect(clipped, hasLength(10000));
    expect(clipped.first.timestamp, merged[2000].timestamp);
    expect(clipped.last.timestamp, merged.last.timestamp);
  });

  test('linear merge keeps only one candle at a genuine overlapping boundary',
      () {
    const earlier = [
      MarketBar(1000, TradeCandle(10, 12, 9, 11)),
      MarketBar(3000, TradeCandle(11, 13, 10, 12)),
      MarketBar(5000, TradeCandle(12, 14, 11, 13)),
    ];
    const next = [
      MarketBar(3000, TradeCandle(11, 13, 10, 12)),
      MarketBar(4000, TradeCandle(12, 14, 11, 13)),
      MarketBar(5000, TradeCandle(12, 14, 11, 13)),
      MarketBar(7000, TradeCandle(13, 15, 12, 14)),
    ];
    final merged = MarketCandleStore.mergeVerified(earlier, next);
    expect(merged.map((bar) => bar.timestamp).toList(),
        [1000, 3000, 4000, 5000, 7000]);
  });

  test('clipped older overlap still rejects changed confirmed OHLC', () {
    const existing = [
      MarketBar(1000, TradeCandle(10, 12, 9, 11)),
      MarketBar(2000, TradeCandle(11, 13, 10, 12)),
      MarketBar(3000, TradeCandle(12, 14, 11, 13)),
    ];
    const incoming = [
      MarketBar(1000, TradeCandle(10, 13, 9, 12)),
      MarketBar(4000, TradeCandle(13, 15, 12, 14)),
    ];
    // A maxCount of one must not conceal a corrupt historical overlap.
    expect(() => MarketCandleStore.mergeVerified(
        existing, incoming, maxCount: 1),
        throwsA(isA<MarketDataException>()));
    expect(existing.first.candle.high, 12);
  });

}
