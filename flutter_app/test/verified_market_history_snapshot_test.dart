import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/data/verified_market_history_snapshot.dart';

void main() {
  const first = TradeCandle(100, 102, 99, 101);
  const second = TradeCandle(101, 105, 100, 104);
  const third = TradeCandle(104, 106, 102, 103);

  test('cached verified OHLC becomes coherent candle/time arrays', () {
    const bars = <MarketBar>[
      MarketBar(1000, first), MarketBar(3000, second),
    ];
    final snapshot = VerifiedMarketHistorySnapshot.fromVerified(bars);
    expect(snapshot.bars, same(bars));
    expect(snapshot.candles, [first, second]);
    expect(snapshot.timestamps, [1000, 3000]);
    expect(snapshot.timestamps[1] - snapshot.timestamps[0], 2000,
      reason: 'Source gap is not filled by fabricated market bars');
  });

  test('new broker overlap merges only identical timestamps and values', () {
    const cache = <MarketBar>[
      MarketBar(1000, first), MarketBar(3000, second),
    ];
    const response = <MarketBar>[
      MarketBar(3000, second), MarketBar(7000, third),
    ];
    final snapshot = VerifiedMarketHistorySnapshot.mergeVerified(
      cached: cache, fetched: response);
    expect(snapshot.timestamps, [1000, 3000, 7000]);
    expect(snapshot.candles.map((c) => c.close), [101, 104, 103]);
    expect(cache, hasLength(2));
    expect(response, hasLength(2));
    expect(() => snapshot.bars.add(response.last), throwsUnsupportedError);
  });

  test('broker closed-candle revision is rejected instead of replaced', () {
    const cached = <MarketBar>[MarketBar(3000, second)];
    const revised = <MarketBar>[
      MarketBar(3000, TradeCandle(101, 105, 100, 102)),
    ];
    expect(() => VerifiedMarketHistorySnapshot.mergeVerified(
      cached: cached, fetched: revised),
      throwsA(isA<MarketDataException>()));
    expect(cached.single.candle.close, 104);
  });

  test('offload applies at 5000 verified OHLC bars on Flutter mobile', () {
    expect(VerifiedMarketHistorySnapshot.minOffloadBars, 5000);
    expect(VerifiedMarketHistorySnapshot.shouldOffload(4999), isFalse);
    expect(VerifiedMarketHistorySnapshot.shouldOffload(5000), !kIsWeb);
    expect(VerifiedMarketHistorySnapshot.shouldOffload(100000), !kIsWeb);
  });

  test('large cached history worker preserves 12k prices and authentic gaps',
      () async {
    const firstMs = 1700000000000;
    final cached = List<MarketBar>.generate(12000, (i) {
      final timestamp = firstMs + (i + (i >= 6400 ? 1 : 0)) * 60000;
      final price = 4000.0 + i * .02;
      return MarketBar(timestamp,
        TradeCandle(price, price + .5, price - .5, price + .1));
    }, growable: false);
    final snapshot =
        await VerifiedMarketHistorySnapshot.fromVerifiedAsync(cached);
    expect(snapshot.bars, hasLength(12000));
    expect(snapshot.candles, hasLength(12000));
    expect(snapshot.timestamps, hasLength(12000));
    expect(snapshot.timestamps[6400] - snapshot.timestamps[6399], 120000);
    for (final index in [0, 4999, 5000, 6399, 6400, 11999]) {
      expect(snapshot.timestamps[index], cached[index].timestamp);
      expect(snapshot.candles[index].open, cached[index].candle.open);
      expect(snapshot.candles[index].close, cached[index].candle.close);
    }
    expect(cached, hasLength(12000));
  });

  test('large merged worker output aligns 12k cache and 8 fresh bars',
      () async {
    const firstMs = 1700000000000;
    final cached = List<MarketBar>.generate(12000, (i) {
      final p = 3900 + i * .01;
      return MarketBar(firstMs + i * 60000,
          TradeCandle(p, p + 1, p - 1, p + .1));
    }, growable: false);
    final fetched = List<MarketBar>.generate(8, (i) {
      final index = 11999 + i;
      final p = 3900 + index * .01;
      return MarketBar(firstMs + index * 60000,
          TradeCandle(p, p + 1, p - 1, p + .1));
    }, growable: false);
    final snapshot = await VerifiedMarketHistorySnapshot.mergeVerifiedAsync(
      cached: cached, fetched: fetched);
    expect(snapshot.bars, hasLength(12007));
    expect(snapshot.timestamps, hasLength(12007));
    for (final index in [0, 11998, 11999, 12000, 12006]) {
      expect(snapshot.timestamps[index], snapshot.bars[index].timestamp);
      expect(snapshot.candles[index].close,
          snapshot.bars[index].candle.close);
    }
    expect(snapshot.timestamps.last, fetched.last.timestamp);
    expect(cached, hasLength(12000));
    expect(fetched, hasLength(8));
  });

  test('empty verified history creates empty aligned snapshot', () async {
    final snapshot = await VerifiedMarketHistorySnapshot.fromVerifiedAsync(
        const <MarketBar>[]);
    expect(snapshot.bars, isEmpty);
    expect(snapshot.candles, isEmpty);
    expect(snapshot.timestamps, isEmpty);
    final merged = await VerifiedMarketHistorySnapshot.mergeVerifiedAsync(
      cached: const <MarketBar>[], fetched: const <MarketBar>[]);
    expect(merged.timestamps, isEmpty);
  });

  test('Replay index stays tied to source time across reconstructed arrays',
      () async {
    const cached = <MarketBar>[
      MarketBar(1000, first), MarketBar(4000, second),
      MarketBar(9000, third),
    ];
    const cutoffIndex = 1;
    final snapshot =
        await VerifiedMarketHistorySnapshot.fromVerifiedAsync(cached);
    expect(snapshot.timestamps[cutoffIndex], cached[cutoffIndex].timestamp);
    expect(snapshot.candles[cutoffIndex].close,
        cached[cutoffIndex].candle.close);
  });
}
