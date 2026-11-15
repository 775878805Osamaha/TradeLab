import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'replay_training_session.dart';

/// An isolated local archive for historical training. This database is NEVER
/// shared with live orders, the paper journal or broker account credentials.
class ReplayTrainingArchive {
  ReplayTrainingArchive._();

  static Future<Database>? _opening;

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
    if (trades.isEmpty) return;
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
    final db = await _open();
    final rows = await db.query('replay_sessions',
      columns: ['session_id', 'source_key', 'saved_at_ms', 'payload'],
      orderBy: 'saved_at_ms DESC', limit: limit);
    return List<Map<String, Object?>>.unmodifiable(rows.map((row) {
      final payload = jsonDecode(row['payload'] as String);
      if (payload is! Map<String, dynamic> || payload['schema'] != 1) {
        throw const FormatException('Invalid archived replay session');
      }
      return Map<String, Object?>.unmodifiable({
        'sessionId': row['session_id'],
        'sourceKey': row['source_key'],
        'savedAtMs': row['saved_at_ms'],
        'visibleCount': payload['visibleCount'],
        'tradeCount': (payload['trades'] as List).length,
        'realizedPricePnl': payload['realizedPricePnl'],
      });
    }));
  }
}
