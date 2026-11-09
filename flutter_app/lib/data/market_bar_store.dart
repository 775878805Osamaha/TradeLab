import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'market_api.dart';
import 'tradelab_data.dart';

/// On-device archive of *verified provider* OHLC only. Preview candles are
/// never written, and cTrader data is isolated by the authorized account.
/// These historical bars are not live quotes or a replacement for the feed.
class MarketBarStore {
  MarketBarStore({this.fileName = 'tradelab_flutter_market_bars_v1.db'});

  final String fileName;
  Future<Database>? _opening;

  Future<Database> get _db => _opening ??= _open();

  Future<Database> _open() async {
    try {
      final root = await getDatabasesPath();
      return await openDatabase(
        path.join(root, fileName),
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE market_bars (
              source TEXT NOT NULL,
              account TEXT NOT NULL,
              symbol TEXT NOT NULL,
              timeframe TEXT NOT NULL,
              timestamp_ms INTEGER NOT NULL,
              open REAL NOT NULL,
              high REAL NOT NULL,
              low REAL NOT NULL,
              close REAL NOT NULL,
              content_digest TEXT NOT NULL,
              PRIMARY KEY (source, account, symbol, timeframe, timestamp_ms)
            )
          ''');
        },
      );
    } catch (_) {
      // A failed platform-channel/database initialization must be retryable.
      _opening = null;
      rethrow;
    }
  }

  String _scope(TradeSource source, String account) {
    if (source == TradeSource.binance) return 'public';
    if (source == TradeSource.ctrader &&
        RegExp(r'^[1-9][0-9]*$').hasMatch(account)) return account;
    throw const MarketDataException('حساب مصدر الشموع المحفوظة غير صالح.');
  }

  static String _digest(TradeSource source, String account, String symbol,
      String timeframe, MarketBar bar) {
    final candle = bar.candle;
    return sha256.convert(utf8.encode([
      source.name, account, symbol, timeframe, '${bar.timestamp}',
      candle.open.toStringAsPrecision(17),
      candle.high.toStringAsPrecision(17),
      candle.low.toStringAsPrecision(17),
      candle.close.toStringAsPrecision(17),
    ].join('|'))).toString();
  }

  /// Only call this after the API has validated the broker provenance, the
  /// OHLC values and the chronological order of a complete response page.
  Future<void> appendVerified({
    required TradeSource source,
    required String account,
    required String symbol,
    required String timeframe,
    required List<MarketBar> bars,
  }) async {
    final scopedAccount = _scope(source, account);
    if (symbol.isEmpty || timeframe.isEmpty) {
      throw const MarketDataException('مفتاح أرشيف الشموع غير صالح.');
    }
    validateBars(bars);
    if (bars.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      // Bound the SQLite batch size without limiting total historical depth.
      for (var offset = 0; offset < bars.length; offset += 500) {
        final batch = txn.batch();
        final end = (offset + 500).clamp(0, bars.length);
        for (var i = offset; i < end; i++) {
          final bar = bars[i];
          batch.insert('market_bars', {
            'source': source.name,
            'account': scopedAccount,
            'symbol': symbol,
            'timeframe': timeframe,
            'timestamp_ms': bar.timestamp,
            'open': bar.candle.open,
            'high': bar.candle.high,
            'low': bar.candle.low,
            'close': bar.candle.close,
            'content_digest': _digest(source, scopedAccount,
                symbol, timeframe, bar),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
    });
  }

  Future<List<MarketBar>> readLatest({
    required TradeSource source,
    required String account,
    required String symbol,
    required String timeframe,
    int limit = 1200,
  }) => _read(source: source, account: account, symbol: symbol,
      timeframe: timeframe, limit: limit);

  /// Strictly older timestamps avoid duplicates across pages and restarts.
  Future<List<MarketBar>> readOlder({
    required TradeSource source,
    required String account,
    required String symbol,
    required String timeframe,
    required int beforeMs,
    int limit = 1000,
  }) => _read(source: source, account: account, symbol: symbol,
      timeframe: timeframe, beforeMs: beforeMs, limit: limit);

  Future<List<MarketBar>> _read({
    required TradeSource source,
    required String account,
    required String symbol,
    required String timeframe,
    int? beforeMs,
    required int limit,
  }) async {
    final scopedAccount = _scope(source, account);
    if (limit < 1 || limit > 5000 || (beforeMs != null && beforeMs < 1)) {
      throw const MarketDataException('طلب أرشيف الشموع خارج الحدود الآمنة.');
    }
    final db = await _db;
    final rows = await db.query('market_bars',
      where: 'source = ? AND account = ? AND symbol = ? AND timeframe = ?'
          '${beforeMs == null ? '' : ' AND timestamp_ms < ?'}',
      whereArgs: [source.name, scopedAccount, symbol, timeframe,
        if (beforeMs != null) beforeMs],
      orderBy: 'timestamp_ms DESC', limit: limit);
    final bars = rows.map((row) {
      final bar = MarketBar(row['timestamp_ms'] as int,
        TradeCandle(
        (row['open'] as num).toDouble(), (row['high'] as num).toDouble(),
        (row['low'] as num).toDouble(), (row['close'] as num).toDouble(),
      ));
      if (row['content_digest'] != _digest(source, scopedAccount,
          symbol, timeframe, bar)) {
        throw const MarketDataException('فشل التحقق من سلامة الشموع المحفوظة.');
      }
      return bar;
    }).toList(growable: false).reversed.toList(growable: false);
    validateBars(bars);
    return bars;
  }
}
