import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'market_api.dart';
import 'chart_timeframe_catalog.dart';
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
      timestampMs: (row['timestamp_ms'] as num).toInt(),
      volume: (row['volume'] as num?)?.toDouble(),
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

  // Start with enough recent source candles for a fluid Android chart.
  // Deep SQLite history remains on disk until the user pans left.
  static const initialChartPageSize = 4000;
  static const olderChartPageSize = 2000;

  static int olderPageCapacity(int loadedBars) {
    if (loadedBars < 0 ||
        loadedBars > MarketHistoryBudget.maxVisibleTimeCandles) {
      throw ArgumentError.value(
          loadedBars, 'loadedBars', 'Outside chart memory budget');
    }
    final remaining = MarketHistoryBudget.maxVisibleTimeCandles - loadedBars;
    return remaining < olderChartPageSize ? remaining : olderChartPageSize;
  }

  /// Accept only a contiguous cached prefix that directly attaches to the
  /// current oldest chart candle. Stored islands (e.g. bars 1..10 and
  /// 50..100) cannot certify that unarchived bars 11..49 never existed.
  /// For any uncertain gap, fetch the authenticated broker page instead.
  ///
  /// A genuine weekend/holiday may cause a gap as well: without a broker
  /// coverage manifest the source must confirm it. Never synthesize bars.
  static List<MarketBar> contiguousOlderPage({
    required List<MarketBar> source,
    required int beforeMs,
    required String timeframe,
  }) {
    if (beforeMs < 1) {
      throw ArgumentError.value(beforeMs, 'beforeMs',
          'Expected a positive historical cursor');
    }
    if (source.isEmpty) return source;
    validateBars(source);
    if (source.last.timestamp >= beforeMs) {
      throw const MarketDataException(
          'شموع الأرشيف الأقدم تتجاوز حد الشارت الزمني.');
    }
    final step = ChartTimeframeCatalog.fixedOpenStepMs(timeframe);
    if (step == null || source.last.timestamp != beforeMs - step) {
      // An older disconnected archive island or calendar month cannot
      // prove that intermediate broker candles have all been downloaded.
      return const <MarketBar>[];
    }
    var begin = source.length - 1;
    while (begin > 0 &&
        source[begin].timestamp - source[begin - 1].timestamp == step) {
      begin--;
    }
    // Avoid copying even a bounded 2000-bar page if it is all continuous.
    return begin == 0 ? source : source.sublist(begin);
  }

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
            archived.candle.close != incoming.candle.close ||
            conflictingKnownVolume(archived.candle, incoming.candle)) {
          throw const MarketDataException(
            'تعارض بين الشموع المحفوظة وبيانات المصدر. '
            'أوقفنا تحديث الشارت لحماية Replay؛ تحقق من مصدر البيانات.');
        }
        // Equal timestamps have identical validated OHLC. Retain one bar.
        // Do not discard a verified volume if the incoming source omitted it.
        merged.add(incoming.candle.volume == null && archived.candle.volume != null
            ? archived : incoming);
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
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // SQLite preserves existing OHLC rows. Unknown historical volume
          // remains NULL until a verified provider response can enrich it.
          await db.execute('ALTER TABLE candle_history ADD COLUMN volume REAL');
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE candle_history (
            cache_key TEXT NOT NULL,
            timestamp_ms INTEGER NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL,
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

  /// An account-scoped source-verified page from the disk archive. The
  /// exclusive UTC cursor is applied by SQLite BEFORE parsing/allocating
  /// any bars, even when the disk retains far more than 200k candles.
  /// Empty means cache miss, never proof that the broker has no history.
  static Future<List<MarketBar>> readOlder(
      TradeSymbol symbol, String timeframe, String? accountId, {
      required int beforeMs,
      int limit = olderChartPageSize,
  }) async {
    if (beforeMs < 1 || limit < 1 ||
        limit > MarketHistoryBudget.maxVisibleTimeCandles) {
      throw ArgumentError('Invalid bounded older candle cache request');
    }
    final db = await _open();
    final rows = await db.query('candle_history',
      where: 'cache_key = ? AND timestamp_ms < ?',
      whereArgs: [key(symbol, timeframe, accountId), beforeMs],
      orderBy: 'timestamp_ms DESC',
      limit: limit,
    );
    if (MarketCandleDecodePolicy.shouldOffload(rows.length)) {
      return compute<List<Map<String, Object?>>, List<MarketBar>>(
        _decodeArchivedCandleRows, rows,
        debugLabel: 'tradelab-older-candle-sqlite-page',
      );
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
          columns: ['timestamp_ms', 'open', 'high', 'low', 'close', 'volume'],
          where: 'cache_key = ? AND timestamp_ms IN (${List.filled(page.length, '?').join(',')})',
          whereArgs: [cacheKey, ...timestamps],
        );
        final incoming = <int, MarketBar>{
          for (final bar in page) bar.timestamp: bar,
        };
        final enrich = <int, double>{};
        for (final row in archived) {
          final candle = incoming[row['timestamp_ms'] as int]!.candle;
          if ((row['open'] as num).toDouble() != candle.open ||
              (row['high'] as num).toDouble() != candle.high ||
              (row['low'] as num).toDouble() != candle.low ||
              (row['close'] as num).toDouble() != candle.close ||
              (row['volume'] != null && candle.volume != null &&
                (row['volume'] as num).toDouble() != candle.volume)) {
            throw const MarketDataException(
              'تعارض في الشموع التاريخية المؤرشفة. '
              'لم نستبدل أسعارًا سابقة؛ تحقق من بيانات المصدر.');
          }
          if (row['volume'] == null && candle.volume != null) {
            enrich[row['timestamp_ms'] as int] = candle.volume!;
          }
        }
        final batch = txn.batch();
        for (final entry in enrich.entries) {
          batch.update('candle_history', {'volume': entry.value},
            where: 'cache_key = ? AND timestamp_ms = ? AND volume IS NULL',
            whereArgs: [cacheKey, entry.key]);
        }
        for (final bar in page) {
          batch.insert('candle_history', {
            'cache_key': cacheKey,
            'timestamp_ms': bar.timestamp,
            'open': bar.candle.open,
            'high': bar.candle.high,
            'low': bar.candle.low,
            'close': bar.candle.close,
            'volume': bar.candle.volume,
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
