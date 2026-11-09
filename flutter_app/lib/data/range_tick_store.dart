import 'dart:convert';

import 'package:path/path.dart' as path;

import 'market_api.dart';
import 'package:sqflite/sqflite.dart';

/// Persists a complete, verified BID tick window; never persists partial pages.
/// Account IDs are part of the key to prevent cross-account data reuse.
class RangeTickStore {
  static Database? _database;
  static Future<Database>? _opening;

  static Future<Database> _open() {
    if (_database != null) return Future.value(_database!);
    // Prevent two simultaneous chart requests from opening separate handles.
    return _opening ??= _openDatabase().then((db) {
      _database = db;
      return db;
    }).catchError((Object error, StackTrace stack) {
      _opening = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  static Future<Database> _openDatabase() async {
    final root = await getDatabasesPath();
    final db = await openDatabase(
      path.join(root, 'tradelab_range_ticks.db'),
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE range_tick_snapshots (
            cache_key TEXT PRIMARY KEY,
            fetched_at_ms INTEGER NOT NULL,
            prices_json TEXT NOT NULL
          )
        ''');
        await _createArchive(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createArchive(db);
      },
    );
    _database = db;
    return db;
  }

  static Future<List<double>?> readFresh(
    String accountId,
    String symbol, {
    Duration maxAge = const Duration(minutes: 2),
  }) async {
    final db = await _open();
    final key = '$accountId:$symbol';
    final rows = await db.query('range_tick_snapshots',
        where: 'cache_key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final fetched = rows.first['fetched_at_ms'] as int;
    final age = DateTime.now().toUtc().millisecondsSinceEpoch - fetched;
    if (age < 0 || age > maxAge.inMilliseconds) return null;
    final decoded = jsonDecode(rows.first['prices_json'] as String);
    if (decoded is! List || decoded.isEmpty) return null;
    final prices = decoded.map((value) => (value as num).toDouble()).toList();
    if (prices.any((price) => !price.isFinite || price <= 0)) return null;
    return prices;
  }

  static Future<void> saveVerified(
      String accountId, String symbol, List<double> prices) async {
    if (prices.isEmpty || prices.any((price) => !price.isFinite || price <= 0)) {
      throw ArgumentError.value(prices, 'prices', 'Invalid BID tick snapshot');
    }
    final db = await _open();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      // Old snapshots have no replay value; keep storage bounded while
      // historical window archiving is implemented separately.
      await txn.delete('range_tick_snapshots',
          where: 'fetched_at_ms < ?',
          whereArgs: [now - const Duration(days: 1).inMilliseconds]);
      await txn.insert('range_tick_snapshots', {
        'cache_key': '$accountId:$symbol',
        'fetched_at_ms': now,
        'prices_json': jsonEncode(prices),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
  static Future<void> _createArchive(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS range_tick_archive (
        account_id TEXT NOT NULL,
        symbol TEXT NOT NULL,
        timestamp_ms INTEGER NOT NULL,
        bid REAL NOT NULL,
        PRIMARY KEY (account_id, symbol, timestamp_ms)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_range_tick_archive_lookup
      ON range_tick_archive (account_id, symbol, timestamp_ms)
    ''');
  }

  /// Append verified cTrader BID ticks to permanent history. A timestamp
  /// collision is ignored rather than replacing already archived market data.
  static Future<int> appendHistorical(
      String accountId, String symbol, List<MarketTick> ticks) async {
    if (accountId.isEmpty || symbol.isEmpty) {
      throw ArgumentError('An account and symbol are required');
    }
    var previous = -1;
    for (final tick in ticks) {
      if (tick.timestamp < 0 || tick.timestamp < previous ||
          !tick.bid.isFinite || tick.bid <= 0) {
        throw ArgumentError('Historical BID ticks must be ordered and valid');
      }
      previous = tick.timestamp;
    }
    if (ticks.isEmpty) return 0;
    final db = await _open();
    return db.transaction((txn) async {
      var inserted = 0;
      for (final tick in ticks) {
        inserted += await txn.rawInsert('''
          INSERT OR IGNORE INTO range_tick_archive
          (account_id, symbol, timestamp_ms, bid)
          VALUES (?, ?, ?, ?)
        ''', [accountId, symbol, tick.timestamp, tick.bid]) > 0 ? 1 : 0;
      }
      return inserted;
    });
  }

  /// Returns stored ticks in chronological order, including a replay cutoff.
  /// A limited query prevents loading unbounded tick history into memory.
  static Future<List<MarketTick>> readHistorical(
      String accountId, String symbol, {
      required int beforeMs,
      int limit = 10000,
  }) async {
    if (limit < 1 || limit > 100000) {
      throw RangeError.range(limit, 1, 100000, 'limit');
    }
    final db = await _open();
    final rows = await db.query('range_tick_archive',
        columns: ['timestamp_ms', 'bid'],
        where: 'account_id = ? AND symbol = ? AND timestamp_ms < ?',
        whereArgs: [accountId, symbol, beforeMs],
        orderBy: 'timestamp_ms DESC',
        limit: limit);
    return rows.reversed.map((row) => MarketTick(
        row['timestamp_ms'] as int, (row['bid'] as num).toDouble()))
        .toList(growable: false);
  }

}
