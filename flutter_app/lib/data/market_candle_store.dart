import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'market_api.dart';
import 'tradelab_data.dart';

/// Locally archived, source-validated time candles. A broker account is part
/// of the identity: history from one account is never shown as another's.
/// No candle is synthesized between two verified timestamps.
class MarketCandleStore {
  MarketCandleStore._();

  static Database? _database;
  static Future<Database>? _opening;

  static String key(TradeSymbol symbol, String timeframe, String? accountId) {
    if (symbol.source == TradeSource.ctrader &&
        (accountId == null || accountId.isEmpty)) {
      throw ArgumentError('A cTrader account is required for cached candles');
    }
    return '${symbol.source.name}:${accountId ?? 'public'}:${symbol.code}:$timeframe';
  }

  /// Merge verified provider windows by timestamp without inventing gaps.
  /// An already archived *closed* candle must not change silently on refresh:
  /// conflicting broker OHLC indicates a source revision or corrupt archive.
  /// Replay must never inherit those revisions as if its past were unchanged.
  static List<MarketBar> mergeVerified(
      List<MarketBar> existing, List<MarketBar> fetched,
      {int maxCount = 100000}) {
    if (maxCount <= 0) {
      throw ArgumentError.value(maxCount, 'maxCount', 'Must be positive');
    }
    validateBars(existing);
    validateBars(fetched);
    final byTime = <int, MarketBar>{
      for (final bar in existing) bar.timestamp: bar,
    };
    for (final bar in fetched) {
      final archived = byTime[bar.timestamp];
      if (archived != null &&
          (archived.candle.open != bar.candle.open ||
           archived.candle.high != bar.candle.high ||
           archived.candle.low != bar.candle.low ||
           archived.candle.close != bar.candle.close)) {
        throw const MarketDataException(
          'تعارض بين الشموع المحفوظة وبيانات المصدر. '
          'أوقفنا تحديث الشارت لحماية Replay؛ تحقق من مصدر البيانات.');
      }
      byTime[bar.timestamp] = bar;
    }
    final timestamps = byTime.keys.toList()..sort();
    final start = timestamps.length > maxCount ? timestamps.length - maxCount : 0;
    return List<MarketBar>.unmodifiable(
        timestamps.skip(start).map((ts) => byTime[ts]!));
  }

  static Future<Database> _open() async {
    if (_database != null) return _database!;
    final pending = _opening ??= _openDatabase();
    try {
      return _database = await pending;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<Database> _openDatabase() async {
    final root = await getDatabasesPath();
    return openDatabase(path.join(root, 'tradelab_market_candles.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE candle_history (
            cache_key TEXT NOT NULL,
            timestamp_ms INTEGER NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            PRIMARY KEY (cache_key, timestamp_ms)
          )
        ''');
        await db.execute('''
          CREATE TABLE candle_sync (
            cache_key TEXT PRIMARY KEY,
            verified_at_ms INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  /// Returns only stored provider bars in ascending time order; the caller
  /// must additionally verify that the correct source is authenticated.
  static Future<List<MarketBar>> read(
      TradeSymbol symbol, String timeframe, String? accountId,
      {int limit = 100000}) async {
    final db = await _open();
    final rows = await db.query('candle_history',
        where: 'cache_key = ?', whereArgs: [key(symbol, timeframe, accountId)],
        orderBy: 'timestamp_ms DESC', limit: limit);
    final bars = rows.reversed.map((row) => MarketBar(
      row['timestamp_ms'] as int,
      TradeCandle(
        (row['open'] as num).toDouble(),
        (row['high'] as num).toDouble(),
        (row['low'] as num).toDouble(),
        (row['close'] as num).toDouble(),
      ),
    )).toList(growable: false);
    validateBars(bars);
    return bars;
  }

  static Future<bool> isFresh(
      TradeSymbol symbol, String timeframe, String? accountId,
      {Duration maxAge = const Duration(seconds: 90)}) async {
    final db = await _open();
    final rows = await db.query('candle_sync', columns: ['verified_at_ms'],
        where: 'cache_key = ?',
        whereArgs: [key(symbol, timeframe, accountId)], limit: 1);
    if (rows.isEmpty) return false;
    final age = DateTime.now().toUtc().millisecondsSinceEpoch -
        (rows.first['verified_at_ms'] as int);
    return age >= 0 && age <= maxAge.inMilliseconds;
  }

  /// Only call this after the source API has validated OHLC and timestamps.
  /// Older pagination writes do not refresh the latest-price freshness marker.
  static Future<void> archive(TradeSymbol symbol, String timeframe,
      String? accountId, List<MarketBar> bars,
      {bool markFresh = false}) async {
    if (bars.isEmpty) return;
    validateBars(bars);
    final db = await _open();
    final cacheKey = key(symbol, timeframe, accountId);
    await db.transaction((txn) async {
      // Batched writes support long broker history without one transaction per
      // candle and without storing an enormous JSON blob in memory.
      for (var offset = 0; offset < bars.length; offset += 500) {
        final batch = txn.batch();
        for (final bar in bars.skip(offset).take(500)) {
          batch.insert('candle_history', {
            'cache_key': cacheKey,
            'timestamp_ms': bar.timestamp,
            'open': bar.candle.open,
            'high': bar.candle.high,
            'low': bar.candle.low,
            'close': bar.candle.close,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
      if (markFresh) {
        await txn.insert('candle_sync', {
          'cache_key': cacheKey,
          'verified_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
