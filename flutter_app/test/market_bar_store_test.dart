import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_bar_store.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  const testDb = 'tradelab_flutter_market_bars_store_test.db';
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await getDatabasesPath();
    await deleteDatabase(path.join(root, testDb));
  });

  MarketBar bar(int timestamp, double price) => MarketBar(timestamp,
      TradeCandle(price, price + 2, price - 2, price + 1));

  test('verified historical bars survive store recreation and page backwards',
      () async {
    final store = MarketBarStore(fileName: testDb);
    await store.appendVerified(source: TradeSource.ctrader,
      account: '100', symbol: 'XAUUSD', timeframe: '15m',
      bars: [bar(1000, 2010), bar(2000, 2020), bar(3000, 2030),
        bar(4000, 2040), bar(5000, 2050)]);
    final reopened = MarketBarStore(fileName: testDb);
    final recent = await reopened.readLatest(source: TradeSource.ctrader,
      account: '100', symbol: 'XAUUSD', timeframe: '15m', limit: 2);
    expect(recent.map((item) => item.timestamp), [4000, 5000]);
    final older = await reopened.readOlder(source: TradeSource.ctrader,
      account: '100', symbol: 'XAUUSD', timeframe: '15m',
      beforeMs: 4000, limit: 2);
    expect(older.map((item) => item.timestamp), [2000, 3000]);
    final oldest = await reopened.readOlder(source: TradeSource.ctrader,
      account: '100', symbol: 'XAUUSD', timeframe: '15m',
      beforeMs: 2000, limit: 2);
    expect(oldest.map((item) => item.timestamp), [1000]);
  });

  test('broker account, timeframe, symbol and provider are isolated', () async {
    final store = MarketBarStore(fileName: testDb);
    await store.appendVerified(source: TradeSource.ctrader,
      account: '200', symbol: 'XAUUSD', timeframe: '1h',
      bars: [bar(4000, 2100)]);
    for (final query in [
      (TradeSource.ctrader, '201', 'XAUUSD', '1h'),
      (TradeSource.ctrader, '200', 'EURUSD', '1h'),
      (TradeSource.ctrader, '200', 'XAUUSD', '15m'),
      (TradeSource.binance, '200', 'XAUUSD', '1h'),
    ]) {
      final saved = await store.readLatest(source: query.$1,
        account: query.$2, symbol: query.$3, timeframe: query.$4);
      expect(saved, isEmpty);
    }
    await expectLater(store.readLatest(source: TradeSource.ctrader,
      account: 'invalid', symbol: 'XAUUSD', timeframe: '1h'),
      throwsA(isA<MarketDataException>()));
  });

  test('revisions replace a provider bar, without copying synthetic prices',
      () async {
    final store = MarketBarStore(fileName: testDb);
    await store.appendVerified(source: TradeSource.binance,
      account: '', symbol: 'BTCUSDT', timeframe: '1h',
      bars: [bar(1000, 50000)]);
    await store.appendVerified(source: TradeSource.binance,
      account: 'ignored', symbol: 'BTCUSDT', timeframe: '1h',
      bars: [bar(1000, 50500)]);
    final rows = await store.readLatest(source: TradeSource.binance,
      account: '', symbol: 'BTCUSDT', timeframe: '1h');
    expect(rows, hasLength(1));
    expect(rows.single.candle.open, 50500);
    await expectLater(store.appendVerified(source: TradeSource.binance,
      account: '', symbol: 'BTCUSDT', timeframe: '1h',
      bars: [const MarketBar(2000, TradeCandle(10, 9, 8, 10))]),
      throwsA(isA<MarketDataException>()));
  });

  test('tampered but plausible saved OHLC fails its integrity digest',
      () async {
    final store = MarketBarStore(fileName: testDb);
    await store.appendVerified(source: TradeSource.ctrader,
      account: '300', symbol: 'XAUUSD', timeframe: '1D',
      bars: [bar(1000, 2200)]);
    final root = await getDatabasesPath();
    final db = await openDatabase(
      path.join(root, testDb),
      singleInstance: false,
    );
    await db.rawUpdate('''
      UPDATE market_bars SET high = 2300
      WHERE source = ? AND account = ? AND symbol = ? AND timeframe = ?
    ''', ['ctrader', '300', 'XAUUSD', '1D']);
    await db.close();
    await expectLater(store.readLatest(source: TradeSource.ctrader,
      account: '300', symbol: 'XAUUSD', timeframe: '1D'),
      throwsA(isA<MarketDataException>()));
  });
}
