import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Watchlist stars are local UI preferences, not broker subscriptions,
/// paper ledger entries or cloud data.
abstract class WatchlistFavoritesStore {
  Future<Set<String>> load();
  Future<void> save(Set<String> symbols);
  Future<void> close();
}

/// An app-private preferences database. Does not modify the paper journal,
/// cached BID ticks, cTrader account storage or any broker-owned data.
class SqliteWatchlistFavoritesStore implements WatchlistFavoritesStore {
  SqliteWatchlistFavoritesStore({String? databasePath})
      : _databasePath = databasePath;

  final String? _databasePath;
  Future<Database>? _opening;
  Future<void> _pendingWrite = Future<void>.value();

  Future<Database> get _database => _opening ??= _open();

  Future<Database> _open() async {
    final file = _databasePath ??
        path.join(await getDatabasesPath(), 'tradelab_watchlist_v1.db');
    return openDatabase(file, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE favorite_symbols (
          code TEXT PRIMARY KEY NOT NULL
        )
      ''');
      // Only a genuinely new install starts with useful default stars.
      // Once saved, an EMPTY favorites list remains empty across restarts.
      await db.insert('favorite_symbols', {'code': 'XAUUSD'});
      await db.insert('favorite_symbols', {'code': 'EURUSD'});
    });
  }

  @override
  Future<Set<String>> load() async {
    // Always wait for the last committed local edit before reloading.
    await _pendingWrite;
    final db = await _database;
    final rows = await db.query('favorite_symbols', columns: ['code'],
        orderBy: 'code ASC');
    return rows.map((row) => row['code'] as String).toSet();
  }

  @override
  Future<void> save(Set<String> symbols) {
    // Serialize taps: slow SQLite transactions may not overwrite a newer
    // user selection after a rapid star/unstar sequence.
    final snapshot = Set<String>.of(symbols);
    final next = _pendingWrite.catchError((Object _) {}).then((_) async {
      final db = await _database;
      await db.transaction((txn) async {
        await txn.delete('favorite_symbols');
        final batch = txn.batch();
        for (final code in snapshot) {
          batch.insert('favorite_symbols', {'code': code});
        }
        await batch.commit(noResult: true);
      });
    });
    _pendingWrite = next;
    return next;
  }

  @override
  Future<void> close() async {
    try {
      await _pendingWrite;
    } catch (_) {
      // Closing must still release SQLite after a failed disk operation.
    }
    final opening = _opening;
    _opening = null;
    if (opening != null) {
      try { await (await opening).close(); }
      catch (_) { /* The database may not exist on a widget-test host. */ }
    }
  }
}
