import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
// Test-only adapter around the exact production onUpgrade callback.
import 'package:sqflite_common/src/factory.dart' show SqfliteDatabaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_candle_store.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/paper/paper_journal_controller.dart';
import 'package:tradelab_flutter/paper/paper_journal_store.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';
import 'package:tradelab_flutter/paper/paper_trade_service.dart';
import 'package:tradelab_flutter/replay/replay_training_session.dart';

const count=100000;
const start=1700000000000;
const account='migration-gate';
const frame='1m';
const marketFilename='tradelab_market_candles.db';

class _InjectedUpgradeFailure implements Exception {}

// sqflite's global setter requires its internal factory interface.
// Forward the only operations used by the production store and journal.
// Unanticipated operations fail, rather than silently changing the test.
class _ObservedFactory implements SqfliteDatabaseFactory {
  _ObservedFactory(this.delegate,this.root);
  final DatabaseFactory delegate;
  final String root;
  bool inject=true;
  bool sawInjected=false;
  Database? marketDb;
  int? upgradeMicros, rssBefore, rssAfter, maxRssAfter;
  @override
  Future<String> getDatabasesPath() async=>root;
  @override
  Future<Database> openDatabase(String filename,{OpenDatabaseOptions? options}) async {
    if(path.basename(filename)!=marketFilename||options?.onUpgrade==null){
      return delegate.openDatabase(filename,options:options);
    }
    final o=options!;
    final realUpgrade=o.onUpgrade!;
    final opened=await delegate.openDatabase(filename,options:OpenDatabaseOptions(
      version:o.version,onConfigure:o.onConfigure,onCreate:o.onCreate,
      onDowngrade:o.onDowngrade,onOpen:o.onOpen,readOnly:o.readOnly,
      singleInstance:o.singleInstance,
      onUpgrade:(db,oldVersion,newVersion) async{
        expect(oldVersion,1);expect(newVersion,2);
        final clock=Stopwatch()..start();
        final rss=ProcessInfo.currentRss;
        await realUpgrade(db,oldVersion,newVersion);
        clock.stop();
        final columns=await db.rawQuery('PRAGMA table_info(candle_history)');
        expect(columns.any((r)=>r['name']=='volume'),isTrue);
        if(inject){
          sawInjected=true;
          throw _InjectedUpgradeFailure();
        }
        upgradeMicros=clock.elapsedMicroseconds;
        rssBefore=rss;rssAfter=ProcessInfo.currentRss;
        maxRssAfter=ProcessInfo.maxRss;
      },
    ));
    marketDb=opened;
    return opened;
  }
  @override
  dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}

String digest(Object? value)=>sha256.convert(utf8.encode(jsonEncode(value))).toString();
Future<List<Map<String,Object?>>> rows(Database db) =>db.rawQuery(
  'SELECT cache_key,timestamp_ms,open,high,low,close FROM candle_history ORDER BY cache_key,timestamp_ms');
Future<Map<String,Object?>> inspect(Database db) async {
  final records=await rows(db);
  final integrity=await db.rawQuery('PRAGMA integrity_check');
  final columns=await db.rawQuery('PRAGMA table_info(candle_history)');
  final sync=await db.query('candle_sync',orderBy:'cache_key');
  return {'count':records.length,'digest':digest(records),
    'sync_digest':digest(sync),'integrity':integrity.single.values.single,
    'version':await db.getVersion(),'volume_column':columns.any((r)=>r['name']=='volume')};
}
List<MarketBar> fromRows(List<Map<String,Object?>> source)=>[
  for(final r in source) MarketBar(r['timestamp_ms'] as int,TradeCandle(
    (r['open'] as num).toDouble(),(r['high'] as num).toDouble(),
    (r['low'] as num).toDouble(),(r['close'] as num).toDouble()))
];
String barsDigest(List<MarketBar> bars,String key)=>digest([
  for(final b in bars) {'cache_key':key,'timestamp_ms':b.timestamp,
    'open':b.candle.open,'high':b.candle.high,'low':b.candle.low,'close':b.candle.close}
]);

Map<String,Object?> replay(List<MarketBar> history){
  final bars=history.map((b)=>b.candle).toList(growable:false);
  final session=ReplayTrainingSession()..moveTo(bars,1000);
  final entry=bars[999].close;
  session.enter(side:ReplaySide.buy,candles:bars,quantity:2,
    stopLoss:entry-4,takeProfit:entry+4);
  session.enter(side:ReplaySide.sell,candles:bars,quantity:1,
    stopLoss:entry+4,takeProfit:entry-4);
  Map<String,Object?> snapshot()=>{'cutoff':session.visibleCount,
    'open':session.openTradeCount,'pnl':session.realizedPricePnl,
    'trades':session.trades.map((t)=>t.toJson()).toList()};
  session.moveTo(bars,3000);final first=snapshot();
  expect(session.openTradeCount,0);
  session.moveTo(bars,1000);final rewind=snapshot();
  expect(session.openTradeCount,2);
  session.moveTo(bars,3000);final again=snapshot();
  expect(again,first);
  return {'first':first,'rewind':rewind,'again':again};
}

// Actual existing historical trade simulator; not a Pine strategy backtest.
Map<String,Object?> historicalSimulation(List<MarketBar> history){
  final bars=history.map((b)=>b.candle).toList(growable:false);
  final s=ReplayTrainingSession()..moveTo(bars,1);
  for(var i=1;i<bars.length-1000;i+=1000){
    s.moveTo(bars,i);
    final entry=bars[i-1].close;
    s.enter(side:ReplaySide.buy,candles:bars,quantity:1,
      stopLoss:entry-4,takeProfit:entry+4);
    s.moveTo(bars,i+1000);
  }
  expect(s.trades.length,greaterThan(90));
  expect(s.openTradeCount,0);
  return {'trades':s.trades.map((t)=>t.toJson()).toList(),'pnl':s.realizedPricePnl};
}
class _HistoricalQuote implements PaperQuoteProvider{
  _HistoricalQuote(this.quote);
  MarketQuote quote;
  @override
  Future<MarketQuote> fetch(TradeSymbol symbol) async=>quote;
}
Future<Map<String,Object?>> paper(List<MarketBar> history,TradeSymbol symbol,String filename) async {
  // Explicit test quote adapter. Real bid/ask is not stored in OHLC archives.
  var now=history[999].timestamp;
  MarketQuote at(int i)=>MarketQuote(symbol:symbol.code,source:symbol.source,
    bid:history[i].candle.close,ask:history[i].candle.close+.25,
    timestampMs:history[i].timestamp);
  final store=SqlitePaperJournalStore(databasePath:filename);
  final journal=PaperJournalController(store:store);
  await journal.useAccount(account);
  final feed=_HistoricalQuote(at(999));
  final service=PaperTradeService(quotes:feed,journal:journal,nowMs:()=>now);
  try{
    await service.open(symbol:symbol,side:PaperSide.buy,units:2,
      prepared:await service.prepare(symbol));
    final open=journal.entries.single;
    now=history[1004].timestamp;feed.quote=at(1004);
    await service.close(position:open,prepared:await service.prepare(symbol));
    final closed=journal.entries.single;
    expect(closed.kind,LedgerKind.closedTrade);
    final report=calculateLedgerReport(journal.entries);
    return {'entry':closed.entryPrice,'exit':closed.exitPrice,'quantity':closed.quantity,
      'opened':closed.openedAtMs,'closed':closed.timestampMs,
      'pnl':closed.realizedPnl,'net':report.netProfit,'trade_count':report.tradeCount};
  }finally{
    await store.close();journal.dispose();
  }
}

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('actual production upgrade: 100k v1 rollback, backup restore, replay and paper parity',() async{
    final root=await Directory.systemTemp.createTemp('sqlite-v1-safety-');
    final factory=databaseFactoryFfi;
    final observed=_ObservedFactory(factory,root.path);
    databaseFactory=observed;
    final file=path.join(root.path,marketFilename);
    final backup=path.join(root.path,'pre-upgrade.backup');
    final restored=path.join(root.path,'restored-v1.db');
    final symbol=tradeSymbols.firstWhere((s)=>s.code=='XAUUSD');
    final key=MarketCandleStore.key(symbol,frame,account);
    final evidence=<String,Object?>{
      'scope':'desktop Flutter FFI, synthetic historical OHLC, actual production migration callback',
      'git_sha':Platform.environment['GITHUB_SHA'],'run_id':Platform.environment['GITHUB_RUN_ID'],
      'count_expected':count,'production_backup_implemented':false,
      'flutter_strategy_backtest_available':false,
      'kotlin_backtest':'separate legacy engine; not backed by this Flutter archive; not exercised',
    };
    try{
      final db=await factory.openDatabase(file,options:OpenDatabaseOptions(version:1,onCreate:(db,_)async{
        await db.execute('CREATE TABLE candle_history (cache_key TEXT NOT NULL,timestamp_ms INTEGER NOT NULL,open REAL NOT NULL,high REAL NOT NULL,low REAL NOT NULL,close REAL NOT NULL,PRIMARY KEY(cache_key,timestamp_ms))');
        await db.execute('CREATE TABLE candle_sync (cache_key TEXT PRIMARY KEY,verified_at_ms INTEGER NOT NULL)');
      }));
      await db.rawQuery('PRAGMA journal_mode=DELETE');
      // Deterministic 100k real SQLite rows, including one temporal gap.
      await db.execute('WITH RECURSIVE seq(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM seq WHERE i<99999) INSERT INTO candle_history SELECT ?, ?+60000*(i+CASE WHEN i>=50000 THEN 2 ELSE 0 END), 2000.0+(i%31),2002.0+(i%31),1998.0+(i%31),2001.0+(i%31) FROM seq',[key,start]);
      await db.insert('candle_sync',{'cache_key':key,'verified_at_ms':start+10000000000});
      final before=await inspect(db);evidence['before']=before;
      expect(before['count'],count);expect(before['integrity'],'ok');
      final old=fromRows(await rows(db));
      expect(barsDigest(old,key),before['digest']);
      final replayBefore=replay(old),historyBefore=historicalSimulation(old);
      await db.close();
      // Backup of a CLOSED SQLite file with DELETE journal mode. No user files.
      await File(file).copy(backup);
      final hash=sha256.convert(await File(backup).readAsBytes()).toString();
      expect(sha256.convert(await File(file).readAsBytes()).toString(),hash);
      evidence['backup_sha256']=hash;
      evidence['backup_bytes']=await File(backup).length();
      final paperBefore=await paper(old,symbol,path.join(root.path,'paper-before.db'));
      // Reuse the production callback and throw AFTER ALTER, BEFORE commit.
      await expectLater(MarketCandleStore.read(symbol,frame,account),throwsA(anything));
      expect(observed.sawInjected,isTrue,reason:'failure must be inside real callback after ALTER');
      final failed=await factory.openDatabase(file,options:OpenDatabaseOptions(version:1));
      final afterFailure=await inspect(failed);await failed.close();
      expect(afterFailure,before);
      evidence['rollback']=afterFailure;
      evidence['injected_after_alter']=true;
      // Test-only observed retry through production public API.
      observed.inject=false;
      final rss=ProcessInfo.currentRss,clock=Stopwatch()..start();
      final migrated=await MarketCandleStore.read(symbol,frame,account);
      clock.stop();
      evidence['migration_measurements']={
        'callback_microseconds':observed.upgradeMicros,'open_plus_read_microseconds':clock.elapsedMicroseconds,
        'callback_rss_before_bytes':observed.rssBefore,'callback_rss_after_bytes':observed.rssAfter,
        'callback_process_peak_rss_bytes':observed.maxRssAfter,
        'read_process_rss_before_bytes':rss,'read_process_rss_after_bytes':ProcessInfo.currentRss,
        'read_process_peak_rss_bytes':ProcessInfo.maxRss,
      };
      expect(observed.upgradeMicros,isNotNull);
      expect(migrated.length,count);
      expect(barsDigest(migrated,key),before['digest']);
      expect(migrated.every((b)=>b.candle.timestampMs==b.timestamp&&b.candle.volume==null),isTrue);
      expect(migrated[50000].timestamp-migrated[49999].timestamp,180000);
      final after=await inspect(observed.marketDb!);
      expect(after,{...before,'version':2,'volume_column':true});
      evidence['after']=after;
      final replayAfter=replay(migrated),historyAfter=historicalSimulation(migrated);
      expect(replayAfter,replayBefore);expect(historyAfter,historyBefore);
      evidence['replay']={'before':replayBefore,'after':replayAfter,'equal':true};
      evidence['historical_simulator']={'before_sha256':digest(historyBefore),
        'after_sha256':digest(historyAfter),'equal':true,'trade_count':(historyAfter['trades'] as List).length,'pnl':historyAfter['pnl']};
      final paperAfter=await paper(migrated,symbol,path.join(root.path,'paper-after.db'));
      expect(paperAfter,paperBefore);
      evidence['paper']={'before':paperBefore,'after':paperAfter,'equal':true,
        'quotes':'test adapter uses archived close and explicitly synthetic 0.25 spread'};
      await observed.marketDb!.close();
      await File(backup).copy(restored);
      expect(sha256.convert(await File(restored).readAsBytes()).toString(),hash);
      final recovered=await factory.openDatabase(restored,options:OpenDatabaseOptions(version:1));
      final recovery=await inspect(recovered);await recovered.close();
      expect(recovery,before);
      evidence['restored_backup']=recovery;
      evidence['complete']=true;
    }catch(e){
      evidence['complete']=false;evidence['failure']=e.toString();rethrow;
    }finally{
      final out=Directory('build/sqlite_migration_gate')..createSync(recursive:true);
      File(path.join(out.path,'result.json')).writeAsStringSync(jsonEncode(evidence));
      print('SQLITE_MIGRATION_GATE '+jsonEncode(evidence));
    }
  },timeout:const Timeout(Duration(minutes:4)));
}
