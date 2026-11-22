import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'replay_training_session.dart';

/// An isolated local archive for historical training. This database is NEVER
/// shared with live orders, the paper journal or broker account credentials.
class ReplayTrainingArchive {
  ReplayTrainingArchive._();

  static Future<Database>? _opening;
  // A Replay trade may be saved asynchronously while the user immediately
  // switches from the chart to Results. A plain SQLite SELECT can otherwise
  // overtake that pending write and show an incorrect empty history.
  //
  // ChartScreen registers each scheduled write SYNCHRONOUSLY, before its
  // first SQLite await. We track its outcome without consuming or discarding
  // the writer's own error. The latest completed snapshot is authoritative.
  static Future<bool> _pendingVisibleSave = Future<bool>.value(true);

  static void trackScheduledSave(Future<void> write) {
    // Attach the error handler IMMEDIATELY, not in a later microtask after
    // _pendingVisibleSave completes. A failed SQLite Future can complete
    // synchronously before that microtask, yielding an unhandled-zone error.
    // The original writer still receives its own failure notification.
    final outcome = write.then<bool>(
        (_) => true, onError: (Object _) => false);
    _pendingVisibleSave = _pendingVisibleSave.then((_) => outcome);
  }

  static Future<Database> _open() =>
      _opening ??= _openDatabase().catchError((Object error) {
        _opening = null;
        throw error;
      });

  static Future<Database> _openDatabase() async {
    final folder = await getDatabasesPath();
    return openDatabase(path.join(folder, 'tradelab_replay_training.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE replay_sessions (
            session_id TEXT PRIMARY KEY,
            source_key TEXT NOT NULL,
            saved_at_ms INTEGER NOT NULL,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX replay_sessions_latest '
          'ON replay_sessions(saved_at_ms DESC)');
      },
    );
  }

  static Future<void> save({
    required String sessionId,
    required String sourceKey,
    required int visibleCount,
    required List<ReplayTrainingTrade> trades,
  }) async {
    if (sessionId.isEmpty || sourceKey.isEmpty || visibleCount < 0) {
      throw ArgumentError('Replay session identity or cutoff is invalid.');
    }
    final data = jsonEncode({
      'schema': 1,
      'sourceKey': sourceKey,
      'visibleCount': visibleCount,
      'units': 'price-delta-times-quantity',
      'trades': trades.map((trade) => trade.toJson()).toList(growable: false),
      'realizedPricePnl': trades.fold<double>(
          0, (total, trade) => total + trade.realizedPricePnl),
    });
    final db = await _open();
    await db.insert('replay_sessions', {
      'session_id': sessionId,
      'source_key': sourceKey,
      'saved_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      'payload': data,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, Object?>>> recent({int limit = 20}) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100);
    }
    // Freeze the barrier at invocation time: this results view must include
    // every Replay save scheduled before its navigation began. Never display
    // an old snapshot as if a failed trade write meant zero trades.
    final pending = _pendingVisibleSave;
    if (!await pending) {
      throw StateError('A Replay training snapshot could not be saved.');
    }
    final db = await _open();
    final rows = await db.query('replay_sessions',
      columns: ['session_id', 'source_key', 'saved_at_ms', 'payload'],
      orderBy: 'saved_at_ms DESC, session_id DESC', limit: limit);
    return List<Map<String, Object?>>.unmodifiable(rows.map((row) {
      final payload = jsonDecode(row['payload'] as String);
      if (payload is! Map<String, dynamic> || payload['schema'] != 1) {
        throw const FormatException('Invalid archived replay session');
      }
      final trades = payload['trades'];
      if (trades is! List ||
          trades.any((entry) => entry is! Map ||
              (entry['exitIndex'] == null) !=
                  (entry['exitPrice'] == null))) {
        throw const FormatException('Invalid archived Replay trade entries');
      }
      final closed = trades.where(
          (entry) => (entry as Map)['exitIndex'] != null).length;
      return Map<String, Object?>.unmodifiable({
        'sessionId': row['session_id'],
        'sourceKey': row['source_key'],
        'savedAtMs': row['saved_at_ms'],
        'visibleCount': payload['visibleCount'],
        'tradeCount': trades.length,
        'openTradeCount': trades.length - closed,
        'closedTradeCount': closed,
        'realizedPricePnl': payload['realizedPricePnl'],
      });
    }));
  }
}
