import 'dart:convert';

import 'package:path/path.dart' as path;
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
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE range_tick_snapshots (
            cache_key TEXT PRIMARY KEY,
            fetched_at_ms INTEGER NOT NULL,
            prices_json TEXT NOT NULL
          )
        ''');
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
    await db.insert('range_tick_snapshots', {
      'cache_key': '$accountId:$symbol',
      'fetched_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      'prices_json': jsonEncode(prices),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
