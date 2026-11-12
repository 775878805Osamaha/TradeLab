import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_startup_loader.dart';

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
    expect(calls, hasLength(8));
    expect(calls.last, (now - 6 * 24 * hour, now - 3 * 24 * hour - 1));
  });

  test('recovers Friday BID ticks after a closed weekend without fabrication',
      () async {
    var calls = 0;
    final records = <RangeStartupSnapshot>[];
    final result = await RangeStartupLoader.load(
      endMs: now, priceDistance: 1, minimumClosedBars: 2,
      getTicks: (from, to) async {
        calls++;
        if (calls < 8) return const <MarketTick>[];
        return [
          MarketTick(from + 1000, 2010),
          MarketTick(from + 2000, 2011.4),
          MarketTick(from + 3000, 2012.5),
        ];
      },
      onSnapshot: (page) async => records.add(page),
    );
    expect(calls, 8);
    expect(records, hasLength(1));
    expect(result!.closedBars, greaterThanOrEqualTo(2));
    expect(result.fromMs, now - 6 * 24 * hour);
    expect(result.ticks.every((tick) =>
        tick.timestamp <= now - 3 * 24 * hour - 1), isTrue);
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
}
