import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_tick_store.dart';

void main() {
  const sixDaysMs = 6 * 24 * 60 * 60 * 1000;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await getDatabasesPath();
    // Only this test suite uses the fixed RangeTickStore file on CI.
    final dbFile = path.join(root, 'tradelab_range_ticks.db');
    await deleteDatabase(dbFile);
    // Simulate an existing user's v4 database to verify its upgrade.
    final legacy = await openDatabase(dbFile, version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE range_tick_snapshots (
            cache_key TEXT PRIMARY KEY,
            fetched_at_ms INTEGER NOT NULL,
            prices_json TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE range_tick_archive (
            account_id TEXT NOT NULL,
            symbol TEXT NOT NULL,
            timestamp_ms INTEGER NOT NULL,
            bid REAL NOT NULL,
            sequence_no INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (account_id, symbol, timestamp_ms, sequence_no)
          )
        ''');
        await db.execute('''
          CREATE TABLE range_tick_windows (
            account_id TEXT NOT NULL,
            symbol TEXT NOT NULL,
            from_ms INTEGER NOT NULL,
            to_ms INTEGER NOT NULL,
            tick_count INTEGER NOT NULL,
            saved_at_ms INTEGER NOT NULL,
            PRIMARY KEY (account_id, symbol, from_ms, to_ms)
          )
        ''');
        final from = DateTime.utc(2024, 12, 1).millisecondsSinceEpoch;
        await db.insert('range_tick_archive', {
          'account_id': 'v4-account', 'symbol': 'XAUUSD',
          'timestamp_ms': from + 1, 'sequence_no': 0, 'bid': 2400.0,
        });
        await db.insert('range_tick_windows', {
          'account_id': 'v4-account', 'symbol': 'XAUUSD',
          'from_ms': from, 'to_ms': from + sixDaysMs,
          'tick_count': 1, 'saved_at_ms': from,
        });
      },
    );
    await legacy.close();
  });

  test('v4 window manifests migrate without trusting absent digests',
      () async {
    final start = DateTime.utc(2024, 12, 1).millisecondsSinceEpoch;
    expect(await RangeTickStore.readVerifiedWindow(
      'v4-account', 'XAUUSD',
      fromMs: start, toMs: start + sixDaysMs,
    ), isNull);
    // Existing account ticks survive the v5 upgrade.
    expect(await RangeTickStore.readHistorical(
      'v4-account', 'XAUUSD',
      beforeMs: start + 10,
    ), hasLength(1));
  });

  test('archived ticks alone never claim a complete provider window', () async {
    final start = DateTime.utc(2025, 1, 1).millisecondsSinceEpoch;
    final ticks = [MarketTick(start + 500, 2011.25)];
    await RangeTickStore.appendHistorical('unverified-account', 'XAUUSD', ticks);
    final cached = await RangeTickStore.readVerifiedWindow(
      'unverified-account', 'XAUUSD',
      fromMs: start, toMs: start + sixDaysMs,
    );
    expect(cached, isNull);
  });

  test('verified six-day window restores every same-millisecond BID tick',
      () async {
    final start = DateTime.utc(2025, 2, 1).millisecondsSinceEpoch;
    final ticks = [
      MarketTick(start + 100, 2040),
      MarketTick(start + 100, 2040.1),
      MarketTick(start + 200, 2039.8),
      MarketTick(start + sixDaysMs, 2041.5),
    ];
    await RangeTickStore.archiveVerifiedWindow(
      'complete-account', 'XAUUSD', ticks,
      fromMs: start, toMs: start + sixDaysMs,
    );
    final restored = await RangeTickStore.readVerifiedWindow(
      'complete-account', 'XAUUSD',
      fromMs: start, toMs: start + sixDaysMs,
    );
    expect(restored, isNotNull);
    expect(restored!.map((tick) => tick.timestamp).toList(),
        ticks.map((tick) => tick.timestamp).toList());
    expect(restored.map((tick) => tick.bid).toList(),
        ticks.map((tick) => tick.bid).toList());
    expect(await RangeTickStore.readVerifiedWindow(
      'complete-account', 'XAUUSD',
      fromMs: start + 1, toMs: start + sixDaysMs,
    ), isNull);
  });

  test('complete empty market window is cached without synthetic ticks',
      () async {
    final start = DateTime.utc(2025, 3, 1).millisecondsSinceEpoch;
    await RangeTickStore.archiveVerifiedWindow(
      'empty-account', 'XAUUSD', const <MarketTick>[],
      fromMs: start, toMs: start + sixDaysMs,
    );
    expect(await RangeTickStore.readVerifiedWindow(
      'empty-account', 'XAUUSD',
      fromMs: start, toMs: start + sixDaysMs,
    ), isEmpty);
  });

  test('conflicting overlapping BID data cannot replace cached history',
      () async {
    final start = DateTime.utc(2025, 4, 1).millisecondsSinceEpoch;
    await RangeTickStore.archiveVerifiedWindow(
      'conflict-account', 'XAUUSD',
      [MarketTick(start + 1, 2000), MarketTick(start + 2, 2001)],
      fromMs: start, toMs: start + sixDaysMs,
    );
    await expectLater(
      RangeTickStore.archiveVerifiedWindow(
        'conflict-account', 'XAUUSD',
        [MarketTick(start + 1, 2000), MarketTick(start + 2, 2999)],
        fromMs: start, toMs: start + sixDaysMs,
      ),
      throwsStateError,
    );
    final cached = await RangeTickStore.readVerifiedWindow(
      'conflict-account', 'XAUUSD',
      fromMs: start, toMs: start + sixDaysMs,
    );
    expect(cached!.map((tick) => tick.bid).toList(), [2000, 2001]);
  });

  test('tampered cached BID price is rejected despite same tick count',
      () async {
    final start = DateTime.utc(2025, 5, 1).millisecondsSinceEpoch;
    await RangeTickStore.archiveVerifiedWindow(
      'tamper-account', 'XAUUSD',
      [MarketTick(start + 200, 2100), MarketTick(start + 400, 2101)],
      fromMs: start, toMs: start + sixDaysMs,
    );
    final root = await getDatabasesPath();
    final db = await openDatabase(
      path.join(root, 'tradelab_range_ticks.db'),
    );
    await db.rawUpdate('''
      UPDATE range_tick_archive SET bid = ?
      WHERE account_id = ? AND symbol = ? AND timestamp_ms = ?
    ''', [2199.9, 'tamper-account', 'XAUUSD', start + 400]);
    await db.close();
    expect(await RangeTickStore.readVerifiedWindow(
      'tamper-account', 'XAUUSD',
      fromMs: start, toMs: start + sixDaysMs,
    ), isNull);
  });

  test('latest verified window restores fresh timestamped ticks', () async {
    final end = DateTime.now().toUtc().millisecondsSinceEpoch - 1000;
    final from = end - sixDaysMs;
    await RangeTickStore.archiveVerifiedWindow(
      'fresh-account', 'XAUUSD',
      [MarketTick(end - 100, 1950)],
      fromMs: from, toMs: end,
    );
    final ticks = await RangeTickStore.readLatestVerifiedWindow(
      'fresh-account', 'XAUUSD',
    );
    expect(ticks, hasLength(1));
    expect(ticks!.single.timestamp, end - 100);
    expect(ticks.single.bid, 1950);
  });
}
