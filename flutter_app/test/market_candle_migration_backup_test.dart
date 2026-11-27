import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common/src/factory.dart' show SqfliteDatabaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/market_candle_store.dart';
import 'package:tradelab_flutter/data/market_candle_migration_backup.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

const filename='tradelab_market_candles.db';
const start=1700000000000, count=100000;
const account='backup-gate', frame='1m';
Future<String> hash(File file) async=>(await sha256.bind(file.openRead()).first).toString();
String digest(Object? value)=>sha256.convert(utf8.encode(jsonEncode(value))).toString();
Future<Map<String,Object?>> inspect(Database db) async {
  final rows=await db.rawQuery('SELECT cache_key,timestamp_ms,open,high,low,close FROM candle_history ORDER BY cache_key,timestamp_ms');
  return {'count':rows.length,'digest':digest(rows),'version':await db.getVersion(),
    'sync_digest':digest(await db.query('candle_sync',orderBy:'cache_key')),
    'integrity':(await db.rawQuery('PRAGMA integrity_check')).single.values.single};
}
class _Failure implements Exception {}
class _Factory implements SqfliteDatabaseFactory {
  _Factory(this.delegate,this.root);
  final DatabaseFactory delegate;
  final String root;
  bool inject=true, sawBackup=false, injected=false, changedAfterRollback=false;
  String? changedHash;
  Database? opened;
  @override Future<String> getDatabasesPath() async=>root;
  @override Future<Database> openDatabase(String file,{OpenDatabaseOptions? options}) async {
    if(path.basename(file)!=filename||options?.onUpgrade==null){
      return delegate.openDatabase(file,options:options);
    }
    final o=options!;
    final snapshots=Directory(MarketCandleMigrationBackup.directoryFor(file))
      .listSync().whereType<File>().where((f)=>f.path.endsWith('.sqlite')).toList();
    final sourceHash=await hash(File(file));
    sawBackup=false;
    for(final f in snapshots){if(await hash(f)==sourceHash)sawBackup=true;}
    expect(sawBackup,isTrue);
    try{
      final db=await delegate.openDatabase(file,options:OpenDatabaseOptions(
        version:o.version,onConfigure:o.onConfigure,onCreate:o.onCreate,
        onOpen:o.onOpen,onDowngrade:o.onDowngrade,
        readOnly:o.readOnly,singleInstance:o.singleInstance,
        onUpgrade:(db,from,to)async{
          await o.onUpgrade!(db,from,to);
          if(inject){injected=true;throw _Failure();}
        }));
      opened=db;return db;
    }catch(_){
      if(inject&&injected){
        // Test-only change after rollback: proves actual file restoration,
        // not merely SQLite transaction rollback.
        final db=await delegate.openDatabase(file,options:OpenDatabaseOptions(version:1,singleInstance:false));
        await db.rawUpdate('UPDATE candle_history SET close=close+0.25 WHERE timestamp_ms=?',[start]);
        await db.close();
        changedHash=await hash(File(file));
        changedAfterRollback=changedHash!=sourceHash;
      }
      rethrow;
    }
  }
  @override dynamic noSuchMethod(Invocation i)=>super.noSuchMethod(i);
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();sqfliteFfiInit();
  test('100k v1 automatic backup and restore after real callback failure',()async{
    final root=await Directory.systemTemp.createTemp('preupgrade-backup-');
    final factory=databaseFactoryFfi, observed=_Factory(databaseFactoryFfi,root.path);
    databaseFactory=observed;
    final f=path.join(root.path,filename);
    final backupDir=Directory(MarketCandleMigrationBackup.directoryFor(f));
    final symbol=tradeSymbols.firstWhere((s)=>s.code=='XAUUSD');
    final key=MarketCandleStore.key(symbol,frame,account);
    final evidence=<String,Object?>{'run_id':Platform.environment['GITHUB_RUN_ID'],
      'git_sha':Platform.environment['GITHUB_SHA'],'scope':'SQLite FFI, synthetic 100k rows, single owner'};
    try{
      final db=await factory.openDatabase(f,options:OpenDatabaseOptions(version:1,onCreate:(db,_)async{
        await db.execute('CREATE TABLE candle_history(cache_key TEXT NOT NULL,timestamp_ms INTEGER NOT NULL,open REAL NOT NULL,high REAL NOT NULL,low REAL NOT NULL,close REAL NOT NULL,PRIMARY KEY(cache_key,timestamp_ms))');
        await db.execute('CREATE TABLE candle_sync(cache_key TEXT PRIMARY KEY,verified_at_ms INTEGER NOT NULL)');
      }));
      await db.rawQuery('PRAGMA journal_mode=DELETE');
      await db.execute('WITH RECURSIVE seq(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM seq WHERE i<99999) INSERT INTO candle_history SELECT ?,?+60000*i,2000.0+(i%31),2002.0+(i%31),1998.0+(i%31),2001.0+(i%31) FROM seq',[key,start]);
      await db.insert('candle_sync',{'cache_key':key,'verified_at_ms':start});
      final before=await inspect(db);
      expect(before['count'],count);expect(before['integrity'],'ok');
      await db.close();
      final original=await hash(File(f));
      evidence['before']=before;evidence['original_file_sha256']=original;
      evidence['archive_bytes']=await File(f).length();
      await backupDir.create(recursive:true);
      for(var i=1;i<=4;i++){await File(f).copy(path.join(backupDir.path,'v1-to-v2-$i.sqlite'));}
      final unrelated=File(path.join(backupDir.path,'keep.txt'));await unrelated.writeAsString('unmanaged');
      final rss=ProcessInfo.currentRss,clock=Stopwatch()..start();
      await expectLater(MarketCandleStore.read(symbol,frame,account),throwsA(anything));
      clock.stop();
      expect(observed.injected,isTrue);expect(observed.sawBackup,isTrue);
      expect(observed.changedAfterRollback,isTrue);
      expect(await hash(File(f)),original);
      final failed=await factory.openDatabase(f,options:OpenDatabaseOptions(version:1,singleInstance:false));
      final restored=await inspect(failed);await failed.close();
      expect(restored,before);
      final afterFailure=backupDir.listSync().whereType<File>().where((f)=>f.path.endsWith('.sqlite')).toList();
      expect(afterFailure.length,5);expect(await unrelated.exists(),isTrue);
      evidence['failure']={'injected_after_real_alter':observed.injected,'backup_before_upgrade':observed.sawBackup,
        'test_corrupted_file_sha256':observed.changedHash,'restored_file_sha256':await hash(File(f)),
        'restored':restored,'elapsed_us':clock.elapsedMicroseconds,'retained_snapshots':afterFailure.length};
      observed.inject=false;
      final retry=Stopwatch()..start();
      final bars=await MarketCandleStore.read(symbol,frame,account);
      retry.stop();
      expect(bars.length,count);
      expect(bars.every((b)=>b.timestamp==b.candle.timestampMs&&b.candle.volume==null),isTrue);
      final migrated=await inspect(observed.opened!);
      expect(migrated,{...before,'version':2});
      final remaining=backupDir.listSync().whereType<File>().where((f)=>f.path.endsWith('.sqlite')).toList();
      expect(remaining.length,3);expect(await unrelated.exists(),isTrue);
      expect(remaining.every((f)=>!RegExp(r'v1-to-v2-[123]\.sqlite$').hasMatch(f.path)),isTrue);
      evidence['success']={'archive':migrated,'elapsed_open_read_us':retry.elapsedMicroseconds,
        'retained_snapshots':remaining.map((x)=>path.basename(x.path)).toList(),'unrelated_preserved':true};
      evidence['memory']={'rss_before_bytes':rss,'rss_after_bytes':ProcessInfo.currentRss,'peak_process_rss_bytes':ProcessInfo.maxRss};
      await observed.opened!.close();
      final current=await MarketCandleMigrationBackup.open(filename:f,targetVersion:2,
        openTarget:()=>factory.openDatabase(f,options:OpenDatabaseOptions(version:2)));
      expect(await current.getVersion(),2);await current.close();
      expect(backupDir.listSync().whereType<File>().where((f)=>f.path.endsWith('.sqlite')).length,3);
      evidence['current_version_no_new_backup']=true;evidence['complete']=true;
    }catch(e){evidence['complete']=false;evidence['error']=e.toString();rethrow;}
    finally{
      final out=Directory('build/sqlite_migration_backup')..createSync(recursive:true);
      File(path.join(out.path,'result.json')).writeAsStringSync(jsonEncode(evidence));
      print('SQLITE_BACKUP_GATE '+jsonEncode(evidence));
    }
  },timeout:const Timeout(Duration(minutes:4)));
}
