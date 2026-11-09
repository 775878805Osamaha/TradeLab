import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:path/path.dart' as path;

import 'package:sqflite/sqflite.dart';

import 'market_api.dart';

/// Collect a SHA-256 digest without assembling a giant JSON string of ticks.
class _DigestCollector implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}

/// Complete, source-verified broker interval with its original boundaries.
/// Tick timestamps alone cannot reveal periods without any market events.
class VerifiedBidWindow {
  const VerifiedBidWindow({
    required this.fromMs,
    required this.toMs,
    required this.ticks,
  });

  final int fromMs;
  final int toMs;
  final List<MarketTick> ticks;
}

/// A stable pagination position, including same-millisecond ordering.
class ArchivedBidTick {
  const ArchivedBidTick(this.tick, this.sequence);
  final MarketTick tick;
  final int sequence;
}

/// Persists a complete, verified BID tick window; never persists partial pages.
/// Account IDs are part of the key to prevent cross-account data reuse.
class RangeTickStore {
  static Database? _database;
  static Future<Database>? _opening;

  static const verifiedWindowDuration = Duration(days: 6);

  static String _windowDigest(Iterable<MarketTick> ticks) {
    final collector = _DigestCollector();
    final input = sha256.startChunkedConversion(collector);
    for (final tick in ticks) {
      // 17 digits round-trip an IEEE-754 double across SQLite and Dart;
      // order and same-millisecond multiplicity are part of the checksum.
      input.add(utf8.encode(
        '${tick.timestamp}:${tick.bid.toStringAsPrecision(17)}\\n',
      ));
    }
    input.close();
    final digest = collector.digest;
    if (digest == null) throw StateError('Unable to hash BID window');
    return digest.toString();
  }

  static Future<Database> _open() async {
    if (_database != null) return _database!;
    // Share one in-flight open and allow retry after a failed initialization.
    final pending = _opening ??= _openDatabase();
    try {
      final db = await pending;
      _database = db;
      return db;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<Database> _openDatabase() async {
    final root = await getDatabasesPath();
    final db = await openDatabase(
      path.join(root, 'tradelab_range_ticks.db'),
      version: 5,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE range_tick_snapshots (
            cache_key TEXT PRIMARY KEY,
            fetched_at_ms INTEGER NOT NULL,
            prices_json TEXT NOT NULL
          )
        ''');
        await _createArchive(db);
        await _createWindowIndex(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createArchive(db);
        if (oldVersion < 3) await _upgradeArchive(db);
        if (oldVersion < 4) await _createWindowIndex(db);
        if (oldVersion >= 4 && oldVersion < 5) {
          // Old manifests have no cryptographic content verification.
          // Their rows remain archived, but are treated as cache misses.
          await db.execute(
            'ALTER TABLE range_tick_windows ADD COLUMN tick_digest TEXT');
        }
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
        sequence_no INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (account_id, symbol, timestamp_ms, sequence_no)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_range_tick_archive_lookup
      ON range_tick_archive (account_id, symbol, timestamp_ms)
    ''');
  }

  static Future<void> _upgradeArchive(DatabaseExecutor db) async {
    // SQLite cannot change a primary key in place. Keep existing history and
    // add an ordinal so multiple ticks within one millisecond are preserved.
    await db.execute('ALTER TABLE range_tick_archive RENAME TO range_tick_archive_v2');
    // The original index follows the renamed table. Remove it before
    // creating the replacement so the new archive receives its own index.
    await db.execute('DROP INDEX IF EXISTS idx_range_tick_archive_lookup');
    await _createArchive(db);
    await db.execute('''
      INSERT INTO range_tick_archive
        (account_id, symbol, timestamp_ms, sequence_no, bid)
      SELECT account_id, symbol, timestamp_ms, 0, bid
      FROM range_tick_archive_v2
    ''');
    await db.execute('DROP TABLE range_tick_archive_v2');
    // The old index name is held by the renamed table until it is dropped.
    // Recreate it against the new archive after dropping the old table.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_range_tick_archive_lookup
      ON range_tick_archive (account_id, symbol, timestamp_ms)
    ''');
  }


  static Future<void> _createWindowIndex(DatabaseExecutor db) async {
    // Records complete provider responses, not inferred continuity from
    // nearby timestamps. Old v3 rows remain unverified until fetched again.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS range_tick_windows (
        account_id TEXT NOT NULL,
        symbol TEXT NOT NULL,
        from_ms INTEGER NOT NULL,
        to_ms INTEGER NOT NULL,
        tick_count INTEGER NOT NULL,
        tick_digest TEXT NOT NULL,
        saved_at_ms INTEGER NOT NULL,
        PRIMARY KEY (account_id, symbol, from_ms, to_ms)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_range_tick_windows_recent
      ON range_tick_windows (account_id, symbol, to_ms DESC)
    ''');
  }

  /// Only mark a window complete after the provider returned a verified,
  /// ordered, non-truncated response and every tick reached the archive.
  /// If the app closes between the writes, orphan ticks are safe: no
  /// manifest exists, so a later lookup will fetch the provider again.
  static Future<void> archiveVerifiedWindow(
    String accountId,
    String symbol,
    List<MarketTick> ticks, {
    required int fromMs,
    required int toMs,
  }) async {
    if (accountId.isEmpty || symbol.isEmpty || fromMs < 0 || toMs < fromMs ||
        toMs - fromMs != verifiedWindowDuration.inMilliseconds ||
        ticks.any((tick) => tick.timestamp < fromMs || tick.timestamp > toMs)) {
      throw ArgumentError('Invalid verified BID window bounds');
    }
    // appendHistorical checks chronological ordering, exact overlap values
    // and same-millisecond multiplicities, inside its own transaction.
    await appendHistorical(accountId, symbol, ticks);
    final db = await _open();
    await db.transaction((txn) async {
      final counts = await txn.rawQuery('''
        SELECT COUNT(*) AS total FROM range_tick_archive
        WHERE account_id = ? AND symbol = ?
          AND timestamp_ms BETWEEN ? AND ?
      ''', [accountId, symbol, fromMs, toMs]);
      if ((counts.first['total'] as num).toInt() != ticks.length) {
        throw StateError('Archived BID window does not match provider count');
      }
      await txn.insert('range_tick_windows', {
        'account_id': accountId,
        'symbol': symbol,
        'from_ms': fromMs,
        'to_ms': toMs,
        'tick_count': ticks.length,
        'tick_digest': _windowDigest(ticks),
        'saved_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Returns null unless the exact provider interval was archived and its
  /// event count still matches. Empty verified windows return an empty list.
  /// Never infer complete history from a subset of archived tick rows.
  static Future<List<MarketTick>?> readVerifiedWindow(
    String accountId,
    String symbol, {
    required int fromMs,
    required int toMs,
  }) async {
    if (accountId.isEmpty || symbol.isEmpty || fromMs < 0 || toMs < fromMs) {
      throw ArgumentError('Invalid BID window lookup');
    }
    final db = await _open();
    final windows = await db.query('range_tick_windows',
      columns: ['tick_count', 'tick_digest'],
      where: 'account_id = ? AND symbol = ? AND from_ms = ? AND to_ms = ?',
      whereArgs: [accountId, symbol, fromMs, toMs], limit: 1);
    if (windows.isEmpty) return null;
    final rows = await db.query('range_tick_archive',
      columns: ['timestamp_ms', 'bid'],
      where: 'account_id = ? AND symbol = ? AND timestamp_ms BETWEEN ? AND ?',
      whereArgs: [accountId, symbol, fromMs, toMs],
      orderBy: 'timestamp_ms ASC, sequence_no ASC');
    final manifest = windows.single;
    if (rows.length != (manifest['tick_count'] as num).toInt()) {
      return null;
    }
    final expectedDigest = manifest['tick_digest'];
    // A migrated v4 manifest without a digest is intentionally unverified.
    if (expectedDigest is! String || expectedDigest.length != 64) {
      return null;
    }
    final ticks = rows.map((row) => MarketTick(
      (row['timestamp_ms'] as num).toInt(),
      (row['bid'] as num).toDouble(),
    )).toList(growable: false);
    return _windowDigest(ticks) == expectedDigest ? ticks : null;
  }

  /// Reads a requested historical interval from one or more individually
  /// verified broker windows, even when their saved boundaries differ from
  /// today's paging cursor. Every millisecond must be covered by a window
  /// with a matching SHA-256 manifest; arbitrary archived tick rows are not
  /// evidence that quiet trading periods were successfully downloaded.
  ///
  /// Windows are consumed in disjoint millisecond slices, so overlapping
  /// cached windows cannot duplicate genuine same-millisecond broker ticks.
  /// Returns null when any part is missing, damaged or too large; callers
  /// must fetch that requested interval from the verified cTrader provider.
  static Future<List<MarketTick>?> readCoveredInterval(
    String accountId,
    String symbol, {
    required int fromMs,
    required int toMs,
    int maxTicks = 1000000,
  }) async {
    if (accountId.isEmpty || symbol.isEmpty || fromMs < 0 || toMs < fromMs ||
        maxTicks < 1 || maxTicks > 1000000) {
      throw ArgumentError('Invalid verified BID interval lookup');
    }
    final db = await _open();
    final result = <MarketTick>[];
    var cursor = fromMs;
    var attempts = 0;
    while (cursor <= toMs) {
      // Prefer the furthest-ending verified window, but try a few
      // alternatives if a migrated or corrupted manifest fails validation.
      final candidates = await db.query('range_tick_windows',
        columns: ['from_ms', 'to_ms'],
        where: 'account_id = ? AND symbol = ? AND from_ms <= ? AND to_ms >= ?',
        whereArgs: [accountId, symbol, cursor, cursor],
        orderBy: 'to_ms DESC', limit: 8);
      if (candidates.isEmpty) return null;
      List<MarketTick>? validTicks;
      int? coverageEnd;
      for (final row in candidates) {
        if (++attempts > 64) return null;
        final windowFrom = (row['from_ms'] as num).toInt();
        final windowTo = (row['to_ms'] as num).toInt();
        final verified = await readVerifiedWindow(
          accountId, symbol, fromMs: windowFrom, toMs: windowTo);
        if (verified == null) continue;
        validTicks = verified;
        coverageEnd = windowTo;
        break;
      }
      if (validTicks == null || coverageEnd == null) return null;
      final segmentEnd = coverageEnd < toMs ? coverageEnd : toMs;
      for (final tick in validTicks) {
        if (tick.timestamp < cursor) continue;
        if (tick.timestamp > segmentEnd) break;
        result.add(tick);
        if (result.length > maxTicks) return null;
      }
      cursor = segmentEnd + 1;
    }
    return result;
  }

  /// A recent complete window can restore an initial chart after restart.
  /// Older windows are available through readVerifiedWindow only, preventing
  /// stale quotes from being mistaken for current live market data.
  /// Restore the latest complete provider interval, retaining the exact
  /// start timestamp used by the gateway. The next historical request must
  /// start *before this interval*, not before its oldest nonempty tick.
  static Future<VerifiedBidWindow?> readLatestVerifiedWindowWithCoverage(
    String accountId,
    String symbol, {
    Duration maxAge = const Duration(minutes: 2),
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final db = await _open();
    final windows = await db.query('range_tick_windows',
      columns: ['from_ms', 'to_ms'],
      where: 'account_id = ? AND symbol = ? AND to_ms BETWEEN ? AND ?',
      whereArgs: [accountId, symbol, now - maxAge.inMilliseconds, now],
      orderBy: 'to_ms DESC', limit: 1);
    if (windows.isEmpty) return null;
    final row = windows.single;
    final fromMs = (row['from_ms'] as num).toInt();
    final toMs = (row['to_ms'] as num).toInt();
    final ticks = await readVerifiedWindow(
      accountId, symbol, fromMs: fromMs, toMs: toMs);
    if (ticks == null) return null;
    return VerifiedBidWindow(fromMs: fromMs, toMs: toMs, ticks: ticks);
  }

  /// Legacy caller convenience; chart paging should use the coverage-aware
  /// version to avoid re-downloading already verified quiet market periods.
  static Future<List<MarketTick>?> readLatestVerifiedWindow(
    String accountId,
    String symbol, {
    Duration maxAge = const Duration(minutes: 2),
  }) async {
    final window = await readLatestVerifiedWindowWithCoverage(
        accountId, symbol, maxAge: maxAge);
    return window?.ticks;
  }

  /// Append ordered verified BID ticks, preserving same-millisecond events.
  /// Returns the number of newly inserted ticks (duplicates excluded).
  /// Repeated pages use the same within-timestamp ordinal for deduplication.
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
      // total_changes() counts successful INSERTs, not ignored duplicates.
      final before = await txn.rawQuery('SELECT total_changes() AS count');
      final changesBefore = (before.first['count'] as num).toInt();
      var lastTimestamp = -1;
      var sequence = 0;
      // The first page may begin halfway through a millisecond shared
      // with an older page. Reject that ambiguous overlap rather than
      // silently assigning a conflicting ordinal to a different BID price.
      final boundary = await txn.query('range_tick_archive',
          columns: ['bid'],
          where: 'account_id = ? AND symbol = ? AND timestamp_ms = ?',
          whereArgs: [accountId, symbol, ticks.first.timestamp],
          orderBy: 'sequence_no ASC');
      if (boundary.isNotEmpty) {
        final incoming = ticks.takeWhile(
            (tick) => tick.timestamp == ticks.first.timestamp).toList();
        if (incoming.length != boundary.length ||
            incoming.asMap().entries.any((entry) =>
                (boundary[entry.key]['bid'] as num).toDouble() != entry.value.bid)) {
          throw StateError(
              'Overlapping BID tick boundary is ambiguous; refusing to corrupt history');
        }
      }
      // A later page can overlap an existing millisecond with fewer ticks.
      // Reject partial groups rather than treating the page as complete.
      final groupedCounts = <int, int>{};
      for (final tick in ticks) {
        groupedCounts.update(tick.timestamp, (count) => count + 1,
            ifAbsent: () => 1);
      }
      final existingCounts = await txn.rawQuery('''
        SELECT timestamp_ms, COUNT(*) AS total
        FROM range_tick_archive
        WHERE account_id = ? AND symbol = ?
          AND timestamp_ms BETWEEN ? AND ?
        GROUP BY timestamp_ms
      ''', [accountId, symbol, ticks.first.timestamp, ticks.last.timestamp]);
      for (final row in existingCounts) {
        final timestamp = (row['timestamp_ms'] as num).toInt();
        final count = (row['total'] as num).toInt();
        if (groupedCounts[timestamp] != count) {
          throw StateError(
              'Incomplete overlapping BID millisecond; archive unchanged');
        }
      }
      // Batch inserts to avoid one platform-channel round trip per tick.
      // SQLite changes() distinguishes ignored duplicates from new rows.
      for (var offset = 0; offset < ticks.length; offset += 500) {
        final end = offset + 500 < ticks.length ? offset + 500 : ticks.length;
        final batch = txn.batch();
        for (var i = offset; i < end; i++) {
          final tick = ticks[i];
          if (tick.timestamp != lastTimestamp) {
            lastTimestamp = tick.timestamp;
            sequence = 0;
          } else {
            sequence++;
          }
          batch.rawInsert('''
            INSERT OR IGNORE INTO range_tick_archive
            (account_id, symbol, timestamp_ms, sequence_no, bid)
            VALUES (?, ?, ?, ?, ?)
          ''', [accountId, symbol, tick.timestamp, sequence, tick.bid]);
        }
        // Reject conflicting overlaps anywhere in this page, not just at
        // the first timestamp. The transaction rolls back on a mismatch.
        final existing = await txn.query('range_tick_archive',
            columns: ['timestamp_ms', 'sequence_no', 'bid'],
            where: 'account_id = ? AND symbol = ? AND timestamp_ms BETWEEN ? AND ?',
            whereArgs: [accountId, symbol, ticks[offset].timestamp,
                ticks[end - 1].timestamp],
            orderBy: 'timestamp_ms ASC, sequence_no ASC');
        final known = <(int, int), double>{
          for (final row in existing)
            ((row['timestamp_ms'] as num).toInt(),
             (row['sequence_no'] as num).toInt()):
                (row['bid'] as num).toDouble(),
        };
        var checkTime = offset == 0 ? -1 : ticks[offset - 1].timestamp;
        var checkOrdinal = offset == 0 ? -1 : 0;
        if (offset > 0) {
          var index = offset - 1;
          while (index > 0 && ticks[index - 1].timestamp == checkTime) {
            checkOrdinal++;
            index--;
          }
        }
        for (var i = offset; i < end; i++) {
          final tick = ticks[i];
          if (tick.timestamp != checkTime) {
            checkTime = tick.timestamp;
            checkOrdinal = 0;
          } else {
            checkOrdinal++;
          }
          final prior = known[(tick.timestamp, checkOrdinal)];
          if (prior != null && prior != tick.bid) {
            throw StateError('Conflicting BID tick overlap; history unchanged');
          }
        }
        // noResult avoids materializing one Dart result per tick.
        await batch.commit(noResult: true);
      }
      final after = await txn.rawQuery('SELECT total_changes() AS count');
      return (after.first['count'] as num).toInt() - changesBefore;
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
        orderBy: 'timestamp_ms DESC, sequence_no DESC',
        limit: limit);
    return rows.reversed.map((row) => MarketTick(
        row['timestamp_ms'] as int, (row['bid'] as num).toDouble()))
        .toList(growable: false);
  }

  /// Cursor-based archive pagination that never skips same-millisecond ticks.
  /// The cursor is exclusive. Pass the oldest returned row as the next cursor.
  static Future<List<ArchivedBidTick>> readHistoricalPage(
    String accountId,
    String symbol, {
    required int beforeMs,
    int? beforeSequence,
    int limit = 10000,
  }) async {
    if (accountId.isEmpty || symbol.isEmpty) {
      throw ArgumentError('An account and symbol are required');
    }
    if (limit < 1 || limit > 100000) {
      throw RangeError.range(limit, 1, 100000, 'limit');
    }
    if (beforeSequence != null && beforeSequence < 0) {
      throw RangeError.value(beforeSequence, 'beforeSequence');
    }
    final db = await _open();
    final rows = await db.query('range_tick_archive',
      columns: ['timestamp_ms', 'sequence_no', 'bid'],
      where: beforeSequence == null
          ? 'account_id = ? AND symbol = ? AND timestamp_ms < ?'
          : 'account_id = ? AND symbol = ? AND '
            '(timestamp_ms < ? OR (timestamp_ms = ? AND sequence_no < ?))',
      whereArgs: beforeSequence == null
          ? [accountId, symbol, beforeMs]
          : [accountId, symbol, beforeMs, beforeMs, beforeSequence],
      orderBy: 'timestamp_ms DESC, sequence_no DESC',
      limit: limit,
    );
    return rows.reversed.map((row) => ArchivedBidTick(
      MarketTick((row['timestamp_ms'] as num).toInt(),
          (row['bid'] as num).toDouble()),
      (row['sequence_no'] as num).toInt(),
    )).toList(growable: false);
  }

}
