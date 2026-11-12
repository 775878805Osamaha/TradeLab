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
    // sqflite openDatabase defaults to a shared singleton connection.
    // Use a separate handle so closing this test writer cannot close the
    // production RangeTickStore connection.
    final db = await openDatabase(
      path.join(root, 'tradelab_range_ticks.db'),
      singleInstance: false,
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

  test('joins complete cached windows across different session boundaries',
      () async {
    final start = DateTime.utc(2025, 6, 1).millisecondsSinceEpoch;
    final leftEnd = start - 1;
    await RangeTickStore.archiveVerifiedWindow(
      'spanning-account', 'XAUUSD', [
        MarketTick(leftEnd - 3600000, 1990),
        MarketTick(leftEnd, 1991),
        MarketTick(leftEnd, 1991.1),
      ],
      fromMs: leftEnd - sixDaysMs, toMs: leftEnd,
    );
    await RangeTickStore.archiveVerifiedWindow(
      'spanning-account', 'XAUUSD', [
        MarketTick(start, 1992),
        MarketTick(start, 1992.1),
        MarketTick(start + 3600000, 1993),
      ],
      fromMs: start, toMs: start + sixDaysMs,
    );
    final cached = await RangeTickStore.readCoveredInterval(
      'spanning-account', 'XAUUSD',
      fromMs: start - 3600001, toMs: start + 3600000,
    );
    expect(cached!.map((t) => t.bid).toList(),
        [1990, 1991, 1991.1, 1992, 1992.1, 1993]);
  });

  test('overlapping verified windows do not duplicate BID ticks', () async {
    final start = DateTime.utc(2025, 7, 1).millisecondsSinceEpoch;
    const dayMs = 86400000;
    final shared = [
      MarketTick(start + dayMs * 2, 2200),
      MarketTick(start + dayMs * 5, 2201),
    ];
    await RangeTickStore.archiveVerifiedWindow(
      'offset-account', 'XAUUSD', shared,
      fromMs: start, toMs: start + sixDaysMs,
    );
    await RangeTickStore.archiveVerifiedWindow(
      'offset-account', 'XAUUSD', [
        ...shared,
        MarketTick(start + dayMs * 7, 2202),
      ],
      fromMs: start + dayMs * 2,
      toMs: start + dayMs * 2 + sixDaysMs,
    );
    final cached = await RangeTickStore.readCoveredInterval(
      'offset-account', 'XAUUSD',
      fromMs: start + dayMs, toMs: start + dayMs * 7,
    );
    expect(cached!.map((t) => t.bid).toList(), [2200, 2201, 2202]);
  });

  test('one millisecond coverage gap and wrong account are cache misses',
      () async {
    final start = DateTime.utc(2025, 8, 1).millisecondsSinceEpoch;
    await RangeTickStore.archiveVerifiedWindow(
      'gap-account', 'XAUUSD', const <MarketTick>[],
      fromMs: start, toMs: start + sixDaysMs,
    );
    await RangeTickStore.archiveVerifiedWindow(
      'gap-account', 'XAUUSD', const <MarketTick>[],
      fromMs: start + sixDaysMs + 2,
      toMs: start + sixDaysMs * 2 + 2,
    );
    expect(await RangeTickStore.readCoveredInterval(
      'gap-account', 'XAUUSD',
      fromMs: start + sixDaysMs - 1,
      toMs: start + sixDaysMs + 3,
    ), isNull);
    expect(await RangeTickStore.readCoveredInterval(
      'other-account', 'XAUUSD',
      fromMs: start, toMs: start + sixDaysMs,
    ), isNull);
  });

  test('short verified windows support progressive Range startup safely',
      () async {
    final end = DateTime.now().toUtc().millisecondsSinceEpoch - 1000;
    const hourMs = 3600000;
    final firstFrom = end - hourMs;
    final previousFrom = end - 4 * hourMs;
    await RangeTickStore.archiveVerifiedWindow(
      'progressive-account', 'XAUUSD', [
        MarketTick(firstFrom + 1, 2000),
        MarketTick(end - 100, 2010),
      ],
      fromMs: firstFrom, toMs: end,
    );
    await RangeTickStore.archiveVerifiedWindow(
      'progressive-account', 'XAUUSD', [
        MarketTick(previousFrom + 1, 1990),
        MarketTick(firstFrom - 1, 1995),
      ],
      fromMs: previousFrom, toMs: firstFrom - 1,
    );
    final recovered = await RangeTickStore.readCoveredInterval(
      'progressive-account', 'XAUUSD',
      fromMs: previousFrom, toMs: end,
    );
    expect(recovered!.map((tick) => tick.bid).toList(),
        [1990, 1995, 2000, 2010]);
    final latest = await RangeTickStore.readLatestVerifiedWindowWithCoverage(
      'progressive-account', 'XAUUSD',
    );
    expect(latest, isNotNull);
    expect(latest!.fromMs, firstFrom);
    expect(latest.ticks.length, 2);
    expect(await RangeTickStore.readCoveredInterval(
      'progressive-account', 'XAUUSD',
      fromMs: previousFrom - 1, toMs: end,
    ), isNull, reason: 'One missing millisecond is not verified history');
    await expectLater(
      RangeTickStore.archiveVerifiedWindow(
        'progressive-account', 'XAUUSD', const [],
        fromMs: previousFrom - 7 * 86400000,
        toMs: previousFrom,
      ),
      throwsArgumentError,
    );
  });

  test('latest verified window restores fresh timestamped ticks', () async {
    final end = DateTime.now().toUtc().millisecondsSinceEpoch - 1000;
    final from = end - sixDaysMs;
    await RangeTickStore.archiveVerifiedWindow(
      'fresh-account', 'XAUUSD',
      [MarketTick(end - 100, 1950)],
      fromMs: from, toMs: end,
    );
    final restored = await RangeTickStore.readLatestVerifiedWindowWithCoverage(
      'fresh-account', 'XAUUSD',
    );
    expect(restored, isNotNull);
    expect(restored!.fromMs, from);
    expect(restored.toMs, end);
    expect(restored.ticks, hasLength(1));
    expect(restored.ticks.single.timestamp, end - 100);
    expect(restored.ticks.single.bid, 1950);
    // Even if the first broker event occurs near the end of the window,
    // paging should begin before its verified six-day coverage, not before
    // that event. This avoids overlapping cached windows after a restart.
    expect(restored.fromMs - 1, lessThan(restored.ticks.first.timestamp));
  });
}
