import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_candle_store.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory=databaseFactoryFfi;

  test('actual v1 archive upgrades in place with unknown volume and verified backfill', () async {
    final root=await Directory.systemTemp.createTemp('tradelab-v1-migration-');
    await databaseFactory.setDatabasesPath(root.path);
    final gold=tradeSymbols.firstWhere((s)=>s.code=='XAUUSD');
    const account='old-archive', frame='1h';
    const timestamp=1700000000000;
    final key=MarketCandleStore.key(gold,frame,account);
    final db=await databaseFactory.openDatabase(path.join(root.path,'tradelab_market_candles.db'),
      options:OpenDatabaseOptions(version:1,onCreate:(db,version) async{
        await db.execute('CREATE TABLE candle_history (cache_key TEXT NOT NULL, timestamp_ms INTEGER NOT NULL, open REAL NOT NULL, high REAL NOT NULL, low REAL NOT NULL, close REAL NOT NULL, PRIMARY KEY (cache_key,timestamp_ms))');
        await db.execute('CREATE TABLE candle_sync (cache_key TEXT PRIMARY KEY, verified_at_ms INTEGER NOT NULL)');
      }));
    await db.insert('candle_history',{'cache_key':key,'timestamp_ms':timestamp,
      'open':10.0,'high':12.0,'low':9.0,'close':11.0});
    await db.close();

    final initial=await MarketCandleStore.read(gold,frame,account);
    expect(initial,hasLength(1));
    expect(initial.single.candle.timestampMs,timestamp);
    expect(initial.single.candle.close,11);
    expect(initial.single.candle.volume,isNull);
    await MarketCandleStore.archive(gold,frame,account,[
      const MarketBar(timestamp,TradeCandle(10,12,9,11,timestampMs:timestamp,volume:12))
    ]);
    final result=await MarketCandleStore.read(gold,frame,account);
    expect(result.single.candle.volume,12);
    expect(result.single.candle.timestampMs,timestamp);
    expect(result.single.candle.close,11);
  });
}
