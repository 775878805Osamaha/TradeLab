import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/older_candle_prepend.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  const b0 = TradeCandle(100, 102, 99, 101);
  const b1 = TradeCandle(101, 104, 100, 103);
  const b2 = TradeCandle(103, 105, 102, 104);
  const b3 = TradeCandle(104, 106, 103, 105);

  test('sorts authentic older page and keeps gaps without filling data', () {
    const current = <MarketBar>[
      MarketBar(5000, b2), MarketBar(7000, b3),
    ];
    const incoming = <MarketBar>[
      MarketBar(3000, b1), MarketBar(1000, b0),
      MarketBar(3000, b1), MarketBar(5000, b2), // known boundary
    ];
    final result = OlderCandlePrepend.prepare(
      existing: current, older: incoming);
    expect(result.prefix.map((bar) => bar.timestamp), [1000, 3000]);
    expect(result.bars.map((bar) => bar.timestamp),
        [1000, 3000, 5000, 7000]);
    expect(result.timestamps, [1000, 3000, 5000, 7000]);
    expect(result.candles.map((c) => c.close), [101, 103, 104, 105]);
    expect(result.bars[2], same(current.first),
      reason: 'Do not synthesize or rewrite the pre-existing chart bars');
    expect(current, hasLength(2));
    expect(incoming, hasLength(4));
  });

  test('identical duplicate milliseconds collapse but conflicting OHLC fails',
      () {
    const current = <MarketBar>[MarketBar(5000, b3)];
    const conflicting = <MarketBar>[
      MarketBar(3000, b0), MarketBar(3000, b1),
    ];
    expect(() => OlderCandlePrepend.prepare(
      existing: current, older: conflicting),
      throwsA(isA<MarketDataException>()),
    );
    expect(current.single.timestamp, 5000);
    expect(conflicting, hasLength(2));
  });

  test('rejects corrupt old OHLC before touching chart or Replay', () {
    const current = <MarketBar>[MarketBar(5000, b3)];
    const invalid = <MarketBar>[
      MarketBar(1000, TradeCandle(100, 101, 99, 102)),
    ];
    expect(() => OlderCandlePrepend.prepare(
        existing: current, older: invalid),
      throwsA(isA<MarketDataException>()));
    expect(current.single.candle.close, 105);
  });

  test('empty or entirely overlapping page does not copy large history', () {
    const current = <MarketBar>[
      MarketBar(5000, b2), MarketBar(7000, b3),
    ];
    for (final incoming in <List<MarketBar>>[
      const <MarketBar>[],
      const <MarketBar>[MarketBar(5000, b2), MarketBar(7000, b3)],
    ]) {
      final result = OlderCandlePrepend.prepare(
        existing: current, older: incoming);
      expect(result.prefix, isEmpty);
      expect(result.bars, same(current));
      expect(result.candles, isEmpty);
      expect(result.timestamps, isEmpty);
    }
    expect(OlderCandlePrepend.shouldOffload(
      existingCount: 100000, incomingCount: 0), isFalse);
  });

  test('offload threshold protects large chart from synchronous list rebuild',
      () {
    expect(OlderCandlePrepend.minOffloadBars, 5000);
    expect(OlderCandlePrepend.shouldOffload(
      existingCount: 4999, incomingCount: 1), isFalse);
    expect(OlderCandlePrepend.shouldOffload(
      existingCount: 5000, incomingCount: 1), !kIsWeb);
    expect(OlderCandlePrepend.shouldOffload(
      existingCount: 1, incomingCount: 5000), !kIsWeb);
  });

  test('large worker prepend preserves 12k original timestamps and OHLC',
      () async {
    // A realistic fixed 1m sequence with a verified missing minute.
    const time = 1700000000000;
    final current = List<MarketBar>.generate(12000, (i) {
      final timestamp = time + (i + 1000 + (i >= 7000 ? 1 : 0)) * 60000;
      final price = 3900.0 + i * .01;
      return MarketBar(timestamp,
          TradeCandle(price, price + 1, price - 1, price + .2));
    }, growable: false);
    final older = List<MarketBar>.generate(1000, (i) {
      final timestamp = time + i * 60000;
      final price = 3800.0 + i * .01;
      return MarketBar(timestamp,
          TradeCandle(price, price + 1, price - 1, price + .2));
    }, growable: false);
    // A provider can return pages in reverse order. Do this once before
    // prepending, using no fake candle for the 1m hole in current.
    final result = await OlderCandlePrepend.prepareAsync(
      existing: current, older: older.reversed.toList(growable: false));
    expect(result.prefix, hasLength(1000));
    expect(result.bars, hasLength(13000));
    expect(result.candles, hasLength(13000));
    expect(result.timestamps, hasLength(13000));
    expect(result.bars[1000], same(current.first));
    expect(result.timestamps[1000 + 7000] -
        result.timestamps[1000 + 6999], 120000);
    for (final i in [0, 999, 1000, 1001, 7999, 8000, 12999]) {
      expect(result.timestamps[i], result.bars[i].timestamp);
      expect(result.candles[i].close, result.bars[i].candle.close);
    }
    // Existing source arrays must never be re-sorted or mutated.
    expect(current, hasLength(12000));
    expect(current.first.timestamp, time + 1000 * 60000);
  });

  test('Replay source index shifts by prefix length, not wall-clock gaps', () {
    const current = <MarketBar>[
      MarketBar(5000, b2), MarketBar(9000, b3),
    ];
    const older = <MarketBar>[MarketBar(1000, b0)];
    const replayVisibleThrough = 1;
    final result = OlderCandlePrepend.prepare(
      existing: current, older: older);
    final shifted = replayVisibleThrough + result.prefix.length;
    expect(result.bars[shifted - 1].timestamp,
        current[replayVisibleThrough - 1].timestamp);
    expect(result.bars.last.timestamp, 9000);
  });

  test('requires a pre-existing verified chart archive', () {
    expect(() => OlderCandlePrepend.prepare(
      existing: const <MarketBar>[], older: const <MarketBar>[]),
      throwsArgumentError);
  });
}
