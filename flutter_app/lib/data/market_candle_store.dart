import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'market_api.dart';
import 'market_history_budget.dart';
import 'tradelab_data.dart';

/// Parse a dense SQLite result and validate all stored OHLC in a worker.
/// Database I/O happens before this function; no SQLite handles are sent
/// between isolates. Keep identical strict source-integrity checks for both
/// small and large cached histories.
List<MarketBar> _decodeArchivedCandleRows(List<Map<String, Object?>> rows) {
  final bars = rows.reversed.map((row) => MarketBar(
    (row['timestamp_ms'] as num).toInt(),
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

/// Controls when the parse/validation cost warrants a worker isolate.
class MarketCandleDecodePolicy {
  const MarketCandleDecodePolicy._();
  static const minOffloadBars = 5000;

  static bool shouldOffload(int count) =>
      !kIsWeb && count >= minOffloadBars;
}

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
    // The legacy preview could archive a D1/W1/MN1 bar before it closed
    // under a broker-offset session. Keep the old rows on disk, but do not
    // reuse them as immutable confirmed candles under the stricter policy.
    // Only calendar-frame cTrader keys change; high-volume intraday caches
    // retain their existing identities.
    final closedPolicy = symbol.source == TradeSource.ctrader &&
        const {'1D', '1W', '1M'}.contains(timeframe)
        ? ':broker-closed-v2'
        : '';
    return '${symbol.source.name}:${accountId ?? 'public'}:${symbol.code}:$timeframe$closedPolicy';
  }

  /// Merge verified provider windows by timestamp without inventing gaps.
  /// An already archived *closed* candle must not change silently on refresh:
  /// conflicting broker OHLC indicates a source revision or corrupt archive.
  /// Replay must never inherit those revisions as if its past were unchanged.
  static List<MarketBar> mergeVerified(
      List<MarketBar> existing, List<MarketBar> fetched,
      {int maxCount = MarketHistoryBudget.maxVisibleTimeCandles}) {
    if (maxCount <= 0 ||
        maxCount > MarketHistoryBudget.maxVisibleTimeCandles) {
      throw ArgumentError.value(maxCount, 'maxCount', 'Must be positive');
    }
    validateBars(existing);
    validateBars(fetched);
    // validateBars guarantees both inputs are strictly timestamp-ascending.
    // The previous Map + key sort performed O(N log N) work on every refresh.
    // A two-pointer stable merge is O(existing + fetched), using no inferred
    // candles and no extra broker queries. Check conflicting historical
    // overlaps even when a maxCount limit later clips the older prefix.
    final merged = <MarketBar>[];
    var archiveIndex = 0;
    var incomingIndex = 0;
    while (archiveIndex < existing.length && incomingIndex < fetched.length) {
      final archived = existing[archiveIndex];
      final incoming = fetched[incomingIndex];
      if (archived.timestamp < incoming.timestamp) {
        merged.add(archived);
        archiveIndex++;
      } else if (incoming.timestamp < archived.timestamp) {
        merged.add(incoming);
        incomingIndex++;
      } else {
        if (archived.candle.open != incoming.candle.open ||
            archived.candle.high != incoming.candle.high ||
            archived.candle.low != incoming.candle.low ||
            archived.candle.close != incoming.candle.close) {
          throw const MarketDataException(
            'تعارض بين الشموع المحفوظة وبيانات المصدر. '
            'أوقفنا تحديث الشارت لحماية Replay؛ تحقق من مصدر البيانات.');
        }
        // Equal timestamps have identical validated OHLC. Retain one bar.
        merged.add(incoming);
        archiveIndex++;
        incomingIndex++;
      }
    }
    while (archiveIndex < existing.length) {
      merged.add(existing[archiveIndex++]);
    }
    while (incomingIndex < fetched.length) {
      merged.add(fetched[incomingIndex++]);
    }
    final start = merged.length > maxCount ? merged.length - maxCount : 0;
    return List<MarketBar>.unmodifiable(merged.getRange(start, merged.length));
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
      {int limit = MarketHistoryBudget.maxVisibleTimeCandles}) async {
    if (limit < 1 || limit > MarketHistoryBudget.maxVisibleTimeCandles) {
      throw ArgumentError.value(limit, 'limit', 'Outside chart memory budget');
    }
    final db = await _open();
    final rows = await db.query('candle_history',
        where: 'cache_key = ?', whereArgs: [key(symbol, timeframe, accountId)],
        orderBy: 'timestamp_ms DESC', limit: limit);
    if (MarketCandleDecodePolicy.shouldOffload(rows.length)) {
      // Large broker history can require thousands of OHLC allocations and
      // integrity checks. Keep this CPU work off the chart's gesture isolate.
      return compute<List<Map<String, Object?>>, List<MarketBar>>(
        _decodeArchivedCandleRows, rows,
        debugLabel: 'tradelab-verified-candle-sqlite-decode');
    }
    return _decodeArchivedCandleRows(rows);
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
        // List.skip(offset) walks the prefix again on every page, creating
        // quadratic traversal work when archiving tens of thousands of real
        // broker bars. Index-based slices read each incoming candle once.
        final end = offset + 500 < bars.length ? offset + 500 : bars.length;
        final page = bars.getRange(offset, end).toList(growable: false);
        // Query existing rows in one bounded batch (501 bind parameters).
        // Even an older pagination request must not overwrite broker-closed
        // history behind Replay's back. SQLite serializes this transaction.
        final timestamps = page.map((bar) => bar.timestamp).toList(growable: false);
        final archived = await txn.query('candle_history',
          columns: ['timestamp_ms', 'open', 'high', 'low', 'close'],
          where: 'cache_key = ? AND timestamp_ms IN (${List.filled(page.length, '?').join(',')})',
          whereArgs: [cacheKey, ...timestamps],
        );
        final incoming = <int, MarketBar>{
          for (final bar in page) bar.timestamp: bar,
        };
        for (final row in archived) {
          final candle = incoming[row['timestamp_ms'] as int]!.candle;
          if ((row['open'] as num).toDouble() != candle.open ||
              (row['high'] as num).toDouble() != candle.high ||
              (row['low'] as num).toDouble() != candle.low ||
              (row['close'] as num).toDouble() != candle.close) {
            throw const MarketDataException(
              'تعارض في الشموع التاريخية المؤرشفة. '
              'لم نستبدل أسعارًا سابقة؛ تحقق من بيانات المصدر.');
          }
        }
        final batch = txn.batch();
        for (final bar in page) {
          batch.insert('candle_history', {
            'cache_key': cacheKey,
            'timestamp_ms': bar.timestamp,
            'open': bar.candle.open,
            'high': bar.candle.high,
            'low': bar.candle.low,
            'close': bar.candle.close,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
