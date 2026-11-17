import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_candle_store.dart';
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
