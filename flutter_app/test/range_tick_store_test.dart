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
    await deleteDatabase(path.join(root, 'tradelab_range_ticks.db'));
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
