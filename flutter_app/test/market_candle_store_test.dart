import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
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

  test('merging a new broker page preserves verified history and gaps', () {
    const earlier = [
      MarketBar(1000, TradeCandle(10, 12, 9, 11)),
      MarketBar(3000, TradeCandle(11, 13, 10, 12)),
    ];
    const newer = [
      MarketBar(3000, TradeCandle(12, 14, 11, 13)),
      MarketBar(4000, TradeCandle(13, 15, 12, 14)),
    ];
    final merged = MarketCandleStore.mergeVerified(earlier, newer);
    expect(merged.map((bar) => bar.timestamp), [1000, 3000, 4000]);
    expect(merged[1].candle.close, 13);
  });
}
