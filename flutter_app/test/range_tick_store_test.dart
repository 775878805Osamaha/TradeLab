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

  test('large SHA-verified BID window retains every distinct broker event',
      () async {
    final start = DateTime.utc(2025, 2, 15).millisecondsSinceEpoch;
    // Exceeds the isolate threshold; identical timestamps are genuine
    // distinct broker events and must keep their original order.
    final ticks = List<MarketTick>.generate(5200, (i) =>
      MarketTick(start + i ~/ 2, 2000.0 + i / 1000000));
    await RangeTickStore.archiveVerifiedWindow(
      'large-digest-account', 'XAUUSD', ticks,
      fromMs: start, toMs: start + sixDaysMs,
    );
    final restored = await RangeTickStore.readVerifiedWindow(
      'large-digest-account', 'XAUUSD',
      fromMs: start, toMs: start + sixDaysMs,
    );
    expect(restored, isNotNull);
    expect(restored, hasLength(ticks.length));
    expect(restored![0].timestamp, restored[1].timestamp);
    expect(restored[0].bid, ticks.first.bid);
    expect(restored[1].bid, ticks[1].bid);
    expect(restored.last.timestamp, ticks.last.timestamp);
    expect(restored.last.bid, ticks.last.bid);
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

  test('more than 64 contiguous verified short BID windows restore locally',
      () async {
    // A real chart can accumulate many disjoint short startup sessions. An
    // existing verified 6h archive must not trigger an expensive cTrader
    // refetch merely because it spans more than 64 manifests.
    final start = DateTime.utc(2025, 6, 17).millisecondsSinceEpoch;
    const account = 'multi-short-window-account';
    const count = 73;
    const fiveMinutesMs = 5 * 60 * 1000;
    final expected = <double>[];
    for (var i = 0; i < count; i++) {
      final from = start + i * fiveMinutesMs;
      final bid = 2100 + i / 100;
      expected.add(bid);
      final page = <MarketTick>[MarketTick(from + 100, bid)];
      // Preserve multiplicities within individual verified milliseconds.
      if (i == 36) {
        page.add(MarketTick(from + 100, bid + .005));
        expected.add(bid + .005);
      }
      await RangeTickStore.archiveVerifiedWindow(
        account, 'XAUUSD', page,
        fromMs: from, toMs: from + fiveMinutesMs - 1,
      );
    }
    final result = await RangeTickStore.readCoveredInterval(
      account, 'XAUUSD',
      fromMs: start, toMs: start + count * fiveMinutesMs - 1,
    );
    expect(result, isNotNull,
        reason: '73 individually verified windows are all trustworthy');
    expect(result!.map((tick) => tick.bid).toList(), expected);
    expect(result.length, count + 1);
    expect(result[36].timestamp, result[37].timestamp,
        reason: 'Two genuine BID events at the same millisecond remain distinct');
    // One uncovered millisecond is still a hard cache miss.
    expect(await RangeTickStore.readCoveredInterval(
      account, 'XAUUSD',
      fromMs: start - 1,
      toMs: start + count * fiveMinutesMs - 1,
    ), isNull);
    expect(await RangeTickStore.readCoveredInterval(
      'another-account', 'XAUUSD',
      fromMs: start, toMs: start + count * fiveMinutesMs - 1,
    ), isNull);
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

  test('large same-millisecond BID group verifies bounded batches and rollback',
      () async {
    final start = DateTime.utc(2025, 9, 1).millisecondsSinceEpoch;
    const account = 'large-bid-ordinal-account';
    final sameMillisecond = List<MarketTick>.generate(1220,
      (index) => MarketTick(start + 100, 2200 + index / 10000));
    expect(await RangeTickStore.appendHistorical(
        account, 'XAUUSD', sameMillisecond), 1220);
    expect(await RangeTickStore.appendHistorical(
        account, 'XAUUSD', sameMillisecond), 0,
        reason: 'Replayed identical source events cannot duplicate ticks');

    final conflicting = <MarketTick>[
      MarketTick(start + 50, 2199),
      ...List<MarketTick>.generate(1220, (index) =>
        MarketTick(start + 100,
            index == 750 ? 9999 : 2200 + index / 10000)),
      MarketTick(start + 200, 2210),
    ];
    await expectLater(
      RangeTickStore.appendHistorical(account, 'XAUUSD', conflicting),
      throwsStateError,
      reason: 'An interior overlapping BID event crossing a 500-row '
          'batch boundary must cause an atomic rollback',
    );
    final afterFailure = await RangeTickStore.readHistorical(
      account, 'XAUUSD', beforeMs: start + 300, limit: 2000);
    expect(afterFailure, hasLength(1220));
    expect(afterFailure.first.timestamp, start + 100);
    expect(afterFailure[750].bid, sameMillisecond[750].bid);
    expect(afterFailure.last.timestamp, start + 100);

    final valid = <MarketTick>[
      MarketTick(start + 50, 2199),
      ...sameMillisecond,
      MarketTick(start + 200, 2210),
    ];
    expect(await RangeTickStore.appendHistorical(
        account, 'XAUUSD', valid), 2);
    final full = await RangeTickStore.readHistorical(
      account, 'XAUUSD', beforeMs: start + 300, limit: 2000);
    expect(full, hasLength(1222));
    expect(full.first.bid, 2199);
    expect(full[1].bid, sameMillisecond.first.bid);
    expect(full[1220].bid, sameMillisecond.last.bid);
    expect(full.last.bid, 2210);
  });

  test('dense BID millisecond ordinals stay exact over many 500-tick batches',
      () async {
    final start = DateTime.utc(2025, 9, 3).millisecondsSinceEpoch;
    const account = 'dense-source-bid-account';
    final dense = List<MarketTick>.generate(3607,
      (index) => MarketTick(start + 100, 2000 + index / 10000));
    final page = <MarketTick>[
      MarketTick(start + 50, 1999),
      ...dense,
      MarketTick(start + 150, 2100),
      MarketTick(start + 150, 2101),
      MarketTick(start + 200, 2200),
    ];
    expect(await RangeTickStore.appendHistorical(
      account, 'XAUUSD', page), page.length);

    final stored = await RangeTickStore.readHistoricalPage(
      account, 'XAUUSD', beforeMs: start + 201, limit: 5000);
    expect(stored, hasLength(page.length));
    expect(stored.first.sequence, 0);
    expect(stored.first.tick.bid, 1999);
    for (var i = 0; i < dense.length; i++) {
      final actual = stored[i + 1];
      expect(actual.tick.timestamp, start + 100);
      expect(actual.sequence, i,
          reason: 'A 500-row boundary must not change broker event ordinal');
      expect(actual.tick.bid, dense[i].bid);
    }
    expect(stored[dense.length + 1].sequence, 0);
    expect(stored[dense.length + 2].sequence, 1);
    expect(stored.last.sequence, 0);

    // Re-archive exactly the same cTrader source events. All 3611
    // composite keys and prices must match; no duplicate market BID ticks.
    expect(await RangeTickStore.appendHistorical(
      account, 'XAUUSD', page), 0);
    final replayed = await RangeTickStore.readHistoricalPage(
      account, 'XAUUSD', beforeMs: start + 201, limit: 5000);
    expect(replayed, hasLength(page.length));
    expect(replayed[dense.length].sequence, dense.length - 1);
    expect(replayed.last.tick.bid, 2200);
  });

  test('sorted overlap count scan tolerates gaps but rejects partial ms',
      () async {
    final start = DateTime.utc(2025, 9, 2).millisecondsSinceEpoch;
    const account = 'sparse-bid-group-account';
    final base = [
      MarketTick(start + 2, 2001),
      MarketTick(start + 2, 2002),
      MarketTick(start + 6, 2006),
      MarketTick(start + 10, 2010),
    ];
    expect(await RangeTickStore.appendHistorical(account, 'XAUUSD', base), 4);
    final partial = [
      MarketTick(start + 1, 2000),
      MarketTick(start + 2, 2001),
      MarketTick(start + 4, 2004),
      MarketTick(start + 6, 2006),
      MarketTick(start + 8, 2008),
      MarketTick(start + 10, 2010),
    ];
    await expectLater(
      RangeTickStore.appendHistorical(account, 'XAUUSD', partial),
      throwsStateError,
      reason: 'Partial overlapping same-ms group is not verified history',
    );
    final complete = [
      MarketTick(start + 1, 2000),
      MarketTick(start + 2, 2001),
      MarketTick(start + 2, 2002),
      MarketTick(start + 4, 2004),
      MarketTick(start + 6, 2006),
      MarketTick(start + 8, 2008),
      MarketTick(start + 10, 2010),
      MarketTick(start + 12, 2012),
    ];
    expect(await RangeTickStore.appendHistorical(
      account, 'XAUUSD', complete), 4);
    final restored = await RangeTickStore.readHistorical(
      account, 'XAUUSD', beforeMs: start + 13);
    expect(restored.map((tick) => tick.bid).toList(),
        [2000, 2001, 2002, 2004, 2006, 2008, 2010, 2012]);
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

  test('large directly appended BID page rejects late disorder atomically',
      () async {
    final start = DateTime.utc(2026, 11, 18).millisecondsSinceEpoch;
    const account = 'worker-order-reject-account';
    final source = List<MarketTick>.generate(
      6300, (i) => MarketTick(start + i ~/ 2, 3900.0 + i * .0001));
    // The last source event is inside the source window. Only a full
    // verification detects an interior reversal of the broker event order.
    source[6200] = MarketTick(start + 1000, 3900.62);
    await expectLater(
      RangeTickStore.appendHistorical(account, 'XAUUSD', source),
      throwsArgumentError,
    );
    expect(await RangeTickStore.readHistorical(
      account, 'XAUUSD', beforeMs: start + 10000), isEmpty,
      reason: 'Invalid worker-verified page must never enter the archive');
    expect(source, hasLength(6300),
      reason: 'Validation cannot sort, deduplicate or mutate the provider');
  });

  test('invalid 6k-tick source interior never creates a trusted BID manifest',
      () async {
    final start = DateTime.utc(2026, 11, 19).millisecondsSinceEpoch;
    const account = 'worker-archive-reject-account';
    final source = List<MarketTick>.generate(6250,
      (i) => MarketTick(start + i, 3900.0 + i * .0001));
    // First and last timestamps are IN bounds, but the middle is outside.
    // A first/last-only check must be followed by strict worker ordering
    // verification before SQLite is touched.
    source[3100] = MarketTick(start + 200000, 3900.31);
    await expectLater(
      RangeTickStore.archiveVerifiedWindow(
        account, 'XAUUSD', source,
        fromMs: start, toMs: start + 10000,
      ),
      throwsArgumentError,
    );
    expect(await RangeTickStore.readVerifiedWindow(
      account, 'XAUUSD', fromMs: start, toMs: start + 10000,
    ), isNull);
    expect(await RangeTickStore.readHistorical(
      account, 'XAUUSD', beforeMs: start + 250000,
    ), isEmpty);
  });

  test('large invalid BID price fails without modifying previous archive',
      () async {
    final start = DateTime.utc(2026, 11, 20).millisecondsSinceEpoch;
    const account = 'worker-price-atomic-account';
    final initial = [MarketTick(start + 1, 2000),
      MarketTick(start + 2, 2001)];
    expect(await RangeTickStore.appendHistorical(account, 'XAUUSD', initial),
        2);
    final bad = List<MarketTick>.generate(6200,
      (i) => MarketTick(start + 100 + i, 2000 + i * .0001));
    bad[6198] = MarketTick(start + 100 + 6198, double.nan);
    await expectLater(
      RangeTickStore.appendHistorical(account, 'XAUUSD', bad),
      throwsArgumentError,
    );
    final retained = await RangeTickStore.readHistorical(
      account, 'XAUUSD', beforeMs: start + 10000);
    expect(retained.map((tick) => tick.bid), [2000, 2001],
      reason: 'A failed validation cannot leave partly committed BID ticks');
    expect(bad[6198].bid.isNaN, isTrue);
  });
}
