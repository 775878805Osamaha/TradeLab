import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_startup_loader.dart';
import 'package:tradelab_flutter/data/range_bar_timeline.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 18).millisecondsSinceEpoch;
  const minute = 60 * 1000;
  const hour = 60 * minute;

  test('returns authentic recent Range bars without a six-day wait', () async {
    final requests = <(int, int)>[];
    final seen = <RangeStartupSnapshot>[];
    final snapshot = await RangeStartupLoader.load(
      endMs: now, priceDistance: 1.0, minimumClosedBars: 2,
      getTicks: (from, to) async {
        requests.add((from, to));
        return [
          MarketTick(to - 3000, 100),
          MarketTick(to - 2000, 101.5),
          MarketTick(to - 1000, 102.5),
        ];
      },
      onSnapshot: (batch) async => seen.add(batch),
    );
    expect(requests, [(now - 5 * minute, now)]);
    expect(snapshot, isNotNull);
    expect(snapshot!.fromMs, now - 5 * minute);
    expect(snapshot.ticks, hasLength(3));
    expect(snapshot.closedBars, greaterThanOrEqualTo(2));
    expect(snapshot.timeline.endTickIndices, isNotEmpty);
    expect(seen, hasLength(1));
  });

  test('widens only the missing disjoint older interval', () async {
    final requests = <(int, int)>[];
    final seen = <RangeStartupSnapshot>[];
    final snapshot = await RangeStartupLoader.load(
      endMs: now, priceDistance: 1.0, minimumClosedBars: 1,
      getTicks: (from, to) async {
        requests.add((from, to));
        if (requests.length == 1) {
          return [MarketTick(to - 1, 100)];
        }
        return [
          MarketTick(to - 10, 97),
          MarketTick(to - 9, 98),
          MarketTick(to - 8, 99),
        ];
      },
      onSnapshot: (batch) async => seen.add(batch),
    );
    expect(requests, [
      (now - 5 * minute, now),
      (now - 15 * minute, now - 5 * minute - 1),
    ]);
    expect(snapshot!.fromMs, now - 15 * minute);
    expect(snapshot.ticks.map((tick) => tick.bid).toList(),
        [97, 98, 99, 100]);
    expect(seen, hasLength(2));
    expect(seen.last.timeline.bars.length, greaterThan(1));
  });

  test('stops at six days and reports no authentic market ticks', () async {
    final calls = <(int, int)>[];
    final snapshot = await RangeStartupLoader.load(
      endMs: now, priceDistance: 10.0,
      getTicks: (from, to) async {
        calls.add((from, to));
        return const [];
      },
      onSnapshot: (_) async => fail('No broker data must not create candles'),
    );
    expect(snapshot, isNull);
    expect(calls, hasLength(RangeStartupLoader.horizons.length));
    expect(calls.last, (now - 6 * 24 * hour, now - 132 * hour - 1));
    for (var i = 1; i < calls.length; i++) {
      expect(calls[i].$2, calls[i - 1].$1 - 1,
        reason: 'Authentic BID windows remain fully adjacent');
      expect(calls[i].$2 - calls[i].$1, lessThanOrEqualTo(12 * hour),
        reason: 'Weekend lookback never requests a dense 48h chunk');
    }
  });

  test('recovers Friday BID ticks after a closed weekend without fabrication',
      () async {
    var calls = 0;
    final records = <RangeStartupSnapshot>[];
    final result = await RangeStartupLoader.load(
      endMs: now, priceDistance: 1, minimumClosedBars: 2,
      getTicks: (from, to) async {
        calls++;
        if (calls < 10) return const <MarketTick>[];
        return [
          MarketTick(from + 1000, 2010),
          MarketTick(from + 2000, 2011.4),
          MarketTick(from + 3000, 2012.5),
        ];
      },
      onSnapshot: (page) async => records.add(page),
    );
    expect(calls, 10);
    expect(records, hasLength(1));
    expect(result!.closedBars, greaterThanOrEqualTo(2));
    expect(result.fromMs, now - 48 * hour);
    expect(result.ticks.every((tick) =>
        tick.timestamp <= now - 36 * hour - 1), isTrue);
  });

  test('rejects out-of-window and unordered provider ticks', () async {
    for (final corrupt in [
      [MarketTick(now + 1, 100)],
      [MarketTick(now - 2, 100), MarketTick(now - 3, 101)],
    ]) {
      await expectLater(
        RangeStartupLoader.load(
          endMs: now, priceDistance: 10,
          getTicks: (_, __) async => corrupt,
          onSnapshot: (_) async => fail('Malformed data must not draw'),
        ),
        throwsA(isA<MarketDataException>()),
      );
    }
  });

  test('same-ms broker events are retained without cross-page duplicates',
      () async {
    var call = 0;
    final snapshot = await RangeStartupLoader.load(
      endMs: now, priceDistance: 1.0, minimumClosedBars: 5,
      getTicks: (from, to) async {
        call++;
        if (call == 1) {
          return [
            MarketTick(from, 101),
            MarketTick(from, 101.1),
            MarketTick(from + 1, 101.2),
          ];
        }
        return [
          MarketTick(to, 100),
          MarketTick(to, 100.5),
        ];
      },
      onSnapshot: (_) async {},
    );
    expect(snapshot, isNotNull);
    final ticks = snapshot!.ticks;
    for (var i = 1; i < ticks.length; i++) {
      expect(ticks[i].timestamp, greaterThanOrEqualTo(ticks[i - 1].timestamp));
    }
    expect(ticks.where((x) => x.timestamp == now - 5 * minute), hasLength(2));
    expect(ticks.where((x) => x.timestamp == now - 5 * minute - 1), hasLength(2));
  });
  test('each older BID page publishes an immutable independent snapshot',
      () async {
    final recentProviderPage = <MarketTick>[MarketTick(now - 1000, 200)];
    final received = <RangeStartupSnapshot>[];
    var calls = 0;
    final completed = await RangeStartupLoader.load(
      endMs: now, priceDistance: 1, minimumClosedBars: 2,
      getTicks: (from, to) async {
        calls++;
        if (calls == 1) return recentProviderPage;
        if (calls == 2) {
          return [
            MarketTick(to - 3, 197),
            MarketTick(to - 2, 198.5),
            MarketTick(to - 1, 199.5),
          ];
        }
        return <MarketTick>[];
      },
      onSnapshot: (batch) async => received.add(batch),
    );
    expect(completed, isNotNull);
    expect(received.length, greaterThanOrEqualTo(2));
    expect(received.first.ticks.map((t) => t.bid), [200]);
    expect(completed!.ticks.map((t) => t.bid), [197, 198.5, 199.5, 200]);
    expect(identical(received.first.ticks, completed.ticks), isFalse);
    expect(
      () => completed.ticks.add(MarketTick(now, 210)),
      throwsUnsupportedError,
      reason: 'Published BID history must not be changed by UI or provider',
    );
    // The gateway can release or reuse its page buffer after it returns.
    // A published snapshot still owns exactly the verified market events.
    recentProviderPage.add(MarketTick(now, 999));
    expect(received.first.ticks.map((t) => t.bid), [200]);
    expect(completed.ticks.map((t) => t.bid), [197, 198.5, 199.5, 200]);
    expect(received.last.timeline.bars.length,
        completed.timeline.bars.length);
  });

  test('large first startup BID page builds one immutable source snapshot',
      () async {
    final page = List<MarketTick>.generate(6201, (i) =>
        MarketTick(now - 12000 + i ~/ 2, 2000 + (i % 19) * .08));
    final expected = RangeBarTimeline.build(page, .5);
    final observed = <RangeStartupSnapshot>[];
    var calls = 0;
    final result = await RangeStartupLoader.load(
      endMs: now, priceDistance: .5, minimumClosedBars: 1,
      getTicks: (from, to) async {
        calls++;
        expect((from, to), (now - 5 * minute, now));
        return page;
      },
      onSnapshot: (batch) async => observed.add(batch),
    );
    expect(calls, 1, reason: 'First verified interval should draw immediately');
    expect(result, isNotNull);
    expect(observed, hasLength(1));
    expect(result!.ticks.length, page.length);
    expect(result.timeline.endTickIndices, expected.endTickIndices);
    expect(result.timeline.endTimestamps, expected.endTimestamps);
    expect(result.closedBars, expected.closedBarCount);
    expect(result.ticks[0].bid, page[0].bid);
    expect(result.ticks[1].timestamp, page[0].timestamp,
        reason: 'Distinct BID events with the same millisecond are retained');
    for (var i = 0; i < expected.bars.length; i++) {
      final a = expected.bars[i];
      final b = result.timeline.bars[i];
      expect((b.open, b.high, b.low, b.close),
          (a.open, a.high, a.low, a.close));
    }
    expect(() => result.ticks.clear(), throwsUnsupportedError);
    page.add(MarketTick(now - 1, 9999));
    expect(result.ticks.length, 6201,
        reason: 'Provider buffer mutations must not affect chart history');
  });

  test('large second startup page prepends and preserves first snapshot',
      () async {
    final recent = <MarketTick>[MarketTick(now - 100, 2000)];
    final older = List<MarketTick>.generate(5300, (i) =>
        MarketTick(now - 15 * minute + i ~/ 2,
            1998 + (i % 17) * .12));
    final source = <MarketTick>[...older, ...recent];
    final reference = RangeBarTimeline.build(source, .5);
    final observed = <RangeStartupSnapshot>[];
    var calls = 0;
    final result = await RangeStartupLoader.load(
      endMs: now, priceDistance: .5, minimumClosedBars: 4,
      getTicks: (from, to) async {
        calls++;
        if (calls == 1) return recent;
        if (calls == 2) {
          expect((from, to),
              (now - 15 * minute, now - 5 * minute - 1));
          return older;
        }
        fail('Two verified pages should provide enough closed Range bars');
      },
      onSnapshot: (snapshot) async => observed.add(snapshot),
    );
    expect(calls, 2);
    expect(observed, hasLength(2));
    expect(observed.first.ticks.map((t) => t.bid), [2000]);
    expect(observed.first.timeline.closedBarCount, 0);
    expect(result!.ticks.length, source.length);
    expect(result.timeline.endTickIndices, reference.endTickIndices);
    expect(result.timeline.endTimestamps, reference.endTimestamps);
    expect(result.closedBars, reference.closedBarCount);
    expect(identical(observed.first.ticks, observed.last.ticks), isFalse);
    expect(result.ticks.first.timestamp, older.first.timestamp);
    expect(result.ticks.last.timestamp, recent.first.timestamp);
    expect(result.timeline.visibleClosedBarsThroughTick(0), 0,
        reason: 'Unrevealed BID ticks must not close future candles');
    expect(() => result.ticks.add(recent.single), throwsUnsupportedError);
  });

  test('verified quiet history keeps coverage without rebuilding BID bars',
      () async {
    var calls = 0;
    final observed = <RangeStartupSnapshot>[];
    final latest = await RangeStartupLoader.load(
      endMs: now, priceDistance: 50, minimumClosedBars: 100,
      getTicks: (from, to) async {
        calls++;
        return calls == 1 ? [MarketTick(to - 1, 100)] : const <MarketTick>[];
      },
      onSnapshot: (batch) async => observed.add(batch),
    );
    expect(calls, RangeStartupLoader.horizons.length);
    expect(latest, isNotNull);
    expect(latest!.fromMs, now - 6 * 24 * hour);
    expect(latest.ticks, hasLength(1));
    expect(latest.timeline.bars, hasLength(1));
    expect(observed, hasLength(2),
        reason: 'First authentic tick and final verified coverage only');
    expect(identical(observed.first.timeline, observed.last.timeline), isTrue,
        reason: 'Empty historical intervals cannot change the Range bars');
    expect(identical(observed.first.ticks, observed.last.ticks), isTrue,
        reason: 'Keep the same verified event list when no older BID arrived');
  });


  test('120k verified startup BID ticks are certified before publication',
      () async {
    final page = List<MarketTick>.generate(120000, (i) =>
        MarketTick(now - 125000 + i ~/ 2, 3900 + (i % 97) * .01),
        growable: false);
    final certified = <(int, int, List<MarketTick>)>[];
    final snapshots = <RangeStartupSnapshot>[];
    final result = await RangeStartupLoader.load(
      endMs: now,
      priceDistance: .5,
      minimumClosedBars: 1,
      isCurrent: () => true,
      getTicks: (from, to) async => page,
      onVerifiedPage: (from, to, ticks) {
        certified.add((from, to, ticks));
        expect(snapshots, isEmpty,
            reason: 'Archive certification precedes chart publication');
      },
      onSnapshot: (snapshot) async {
        expect(certified, hasLength(1),
            reason: 'No Range bars before strict BID verification');
        snapshots.add(snapshot);
      },
    );
    expect(certified, hasLength(1));
    expect(identical(certified.single.$3, page), isTrue);
    expect(result, isNotNull);
    expect(result!.ticks, hasLength(120000));
    expect(result.closedBars, greaterThan(0));
    expect(snapshots, hasLength(1));
  });

  test('invalid large startup BID page is never certified or drawn',
      () async {
    final page = List<MarketTick>.generate(6300, (i) =>
        MarketTick(now - 12000 + i, 3900 + i * .001));
    page[6299] = MarketTick(now + 1000, 3900);
    var certified = 0;
    var snapshots = 0;
    await expectLater(
      RangeStartupLoader.load(
        endMs: now,
        priceDistance: 1,
        getTicks: (_, __) async => page,
        onVerifiedPage: (_, __, ___) => certified++,
        onSnapshot: (_) async => snapshots++,
      ),
      throwsA(isA<MarketDataException>()),
    );
    expect(certified, 0);
    expect(snapshots, 0);
  });

  test('broker-confirmed empty windows are archived without fake bars',
      () async {
    final certified = <(int, int)>[];
    final source = await RangeStartupLoader.load(
      endMs: now,
      priceDistance: 1,
      getTicks: (from, to) async => const <MarketTick>[],
      onVerifiedPage: (from, to, ticks) {
        expect(ticks, isEmpty);
        certified.add((from, to));
      },
      onSnapshot: (_) async => fail('No source ticks means no Range bar'),
    );
    expect(source, isNull);
    expect(certified, hasLength(RangeStartupLoader.horizons.length));
    for (var i = 1; i < certified.length; i++) {
      expect(certified[i].$2, certified[i - 1].$1 - 1);
    }
  });

  test('account revision cancellation stops startup archive and snapshots',
      () async {
    var current = true;
    var certified = 0;
    var snapshots = 0;
    final result = await RangeStartupLoader.load(
      endMs: now,
      priceDistance: 1,
      isCurrent: () => current,
      getTicks: (from, to) async {
        // An authenticated response for a previously active account
        // arrives only after the new account/symbol has been selected.
        current = false;
        return [MarketTick(to - 100, 3900)];
      },
      onVerifiedPage: (_, __, ___) => certified++,
      onSnapshot: (_) async => snapshots++,
    );
    expect(result, isNull);
    expect(certified, 0);
    expect(snapshots, 0);
  });

  test('over-memory-cap startup page cannot become trusted cache coverage',
      () async {
    final page = List<MarketTick>.generate(
      RangeStartupLoader.maxStartupTicks + 1,
      (i) => MarketTick(now - 120000 + i ~/ 10, 3900.0),
      growable: false,
    );
    var certified = 0;
    await expectLater(
      RangeStartupLoader.load(
        endMs: now,
        priceDistance: 1,
        getTicks: (_, __) async => page,
        onVerifiedPage: (_, __, ___) => certified++,
        onSnapshot: (_) async => fail('Memory cap must reject publication'),
      ),
      throwsA(isA<MarketDataException>()),
    );
    expect(certified, 0);
  });
  test('Sunday cTrader BID startup reaches Friday in a six-hour page',
      () async {
    // Nov 22, 2026 was Sunday. Friday's real BID ticks are now 42h old,
    // outside the first 36h of authenticated, genuinely empty broker data.
    final sunday = DateTime.utc(2026, 11, 22, 15).millisecondsSinceEpoch;
    final friday = sunday - 42 * hour;
    final requested = <(int, int)>[];
    final snapshots = <RangeStartupSnapshot>[];
    final snapshot = await RangeStartupLoader.load(
      endMs: sunday, priceDistance: 1, minimumClosedBars: 2,
      getTicks: (from, to) async {
        requested.add((from, to));
        if (friday < from || friday + 2 > to) return const <MarketTick>[];
        return [
          MarketTick(friday, 3900.0),
          MarketTick(friday + 1, 3901.5),
          MarketTick(friday + 2, 3902.5),
        ];
      },
      onSnapshot: (page) async => snapshots.add(page),
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.closedBars, greaterThanOrEqualTo(2));
    expect(snapshot.fromMs, sunday - 42 * hour,
      reason: 'Friday BID is verified and published in the 36-42h slice');
    expect(requested, hasLength(9));
    expect(requested.last, (
      sunday - 42 * hour, sunday - 36 * hour - 1));
    for (var index = 1; index < requested.length; index++) {
      expect(requested[index].$2, requested[index - 1].$1 - 1,
          reason: 'No real BID millisecond can be skipped on weekends');
    }
    for (final window in requested.skip(6)) {
      expect(window.$2 - window.$1, lessThan(6 * hour),
          reason: 'Dense first Friday BID pages must remain <= 6h');
    }
    expect(snapshots, hasLength(1));
    expect(snapshot.ticks.map((tick) => tick.timestamp),
      [friday, friday + 1, friday + 2]);
    // No weekend tick, no OHLC-derived range input, no future event.
    expect(snapshot.timeline.bars.first.open, 3900.0);
    expect(snapshot.timeline.endTickIndices.last, 2);
  });


}
