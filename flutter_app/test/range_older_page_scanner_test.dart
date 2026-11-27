import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_older_page.dart';
import 'package:tradelab_flutter/data/range_older_page_scanner.dart';

void main() {
  const step = 12 * 60 * 60 * 1000;
  final last = DateTime.utc(2026, 11, 17).millisecondsSinceEpoch;

  test('one gesture crosses quiet cTrader weekend into genuine BID events',
      () async {
    final calls = <(int, int)>[];
    final found = await RangeOlderPageScanner.scan(
      cursorMs: last,
      alreadyLoaded: 100,
      isCurrent: () => true,
      fetchVerified: (from, to) async {
        calls.add((from, to));
        if (calls.length < 4) return const <MarketTick>[];
        return [
          MarketTick(from, 1900),
          MarketTick(from, 1900.1), // two genuine ticks at one millisecond
          MarketTick(to, 1901.2),
        ];
      },
    );
    expect(found, isNotNull);
    expect(calls.length, 4);
    expect(found!.emptyWindows, 3);
    expect(found.ticks.map((t) => t.bid), [1900, 1900.1, 1901.2]);
    expect(found.ticks[0].timestamp, found.ticks[1].timestamp);
    for (var i = 0; i < calls.length; i++) {
      expect(calls[i].$2 - calls[i].$1, step);
      if (i > 0) {
        expect(calls[i].$2, calls[i - 1].$1 - 1);
      }
    }
    expect(found.nextCursorMs, calls.last.$1 - 1);
    expect(found.fromMs, calls.last.$1);
  });

  test('six quiet pages are bounded and next attempt has no overlap',
      () async {
    final called = <(int, int)>[];
    final first = await RangeOlderPageScanner.scan(
      cursorMs: last,
      alreadyLoaded: 0,
      isCurrent: () => true,
      fetchVerified: (from, to) async {
        called.add((from, to));
        return const <MarketTick>[];
      },
    );
    expect(first!.ticks, isEmpty);
    expect(first.emptyWindows, RangeOlderPageScanner.maxQuietWindowsPerAttempt);
    expect(called, hasLength(6));
    final second = await RangeOlderPageScanner.scan(
      cursorMs: first.nextCursorMs,
      alreadyLoaded: 0,
      maxPages: 1,
      isCurrent: () => true,
      fetchVerified: (from, to) async {
        called.add((from, to));
        return const <MarketTick>[];
      },
    );
    expect(second!.emptyWindows, 1);
    expect(called, hasLength(7));
    expect(called.last.$2, called[5].$1 - 1);
  });

  test('automatic prefill remains one page per network-work budget', () async {
    var count = 0;
    final result = await RangeOlderPageScanner.scan(
      cursorMs: last,
      alreadyLoaded: 500,
      maxPages: 1,
      isCurrent: () => true,
      fetchVerified: (from, to) async {
        count++;
        return const <MarketTick>[];
      },
    );
    expect(count, 1);
    expect(result!.nextCursorMs, last - step - 1);
  });

  test('account or symbol switch cancels scanner after in-flight page',
      () async {
    var active = true;
    var count = 0;
    final result = await RangeOlderPageScanner.scan(
      cursorMs: last,
      alreadyLoaded: 10,
      isCurrent: () => active,
      fetchVerified: (from, to) async {
        count++;
        active = false;
        return const <MarketTick>[];
      },
    );
    expect(result, isNull);
    expect(count, 1);
  });

  test('malformed provider ticks fail closed and are never skipped', () async {
    await expectLater(
      RangeOlderPageScanner.scan(
        cursorMs: last,
        alreadyLoaded: 5,
        isCurrent: () => true,
        fetchVerified: (from, to) async =>
            [MarketTick(from - 1, 2100)],
      ),
      throwsA(isA<MarketDataException>()),
    );
    await expectLater(
      RangeOlderPageScanner.scan(
        cursorMs: last,
        alreadyLoaded: RangeOlderPage.maxLoadedTicks,
        isCurrent: () => true,
        fetchVerified: (from, to) async =>
            [MarketTick(from + 5, 2100)],
      ),
      throwsA(isA<MarketDataException>()),
    );
  });

  test('archive start and invalid limits never cause unbounded scanning',
      () async {
    var calls = 0;
    Future<List<MarketTick>> fetch(int from, int to) async {
      calls++;
      return const <MarketTick>[];
    }
    final result = await RangeOlderPageScanner.scan(
      cursorMs: step - 1,
      alreadyLoaded: 0,
      isCurrent: () => true,
      fetchVerified: fetch,
    );
    expect(result!.ticks, isEmpty);
    expect(calls, 0);
    for (final invalid in [0, 7]) {
      await expectLater(
        RangeOlderPageScanner.scan(
          cursorMs: last,
          alreadyLoaded: 0,
          maxPages: invalid,
          isCurrent: () => true,
          fetchVerified: fetch,
        ),
        throwsArgumentError,
      );
    }
    expect(calls, 0);
  });

  test('archives only verified large broker page after worker validation',
      () async {
    final certified = <(int, int, int)>[];
    final initial = DateTime.utc(2026, 11, 18).millisecondsSinceEpoch;
    final result = await RangeOlderPageScanner.scan(
      cursorMs: initial,
      alreadyLoaded: 500,
      isCurrent: () => true,
      maxPages: 1,
      fetchVerified: (from, to) async {
        // An original verified cTrader page with same-ms BID multiplicity.
        return List<MarketTick>.generate(6200,
            (index) => MarketTick(from + index ~/ 2,
                3900 + index * .0001));
      },
      onVerifiedPage: (from, to, ticks) {
        certified.add((from, to, ticks.length));
      },
    );
    expect(result, isNotNull);
    expect(result!.ticks, hasLength(6200));
    expect(certified, hasLength(1));
    expect(certified.single.$1, result.fromMs);
    expect(certified.single.$2, result.toMs);
    expect(certified.single.$3, 6200);
  });

  test('malformed large BID page is never delivered to archive callback',
      () async {
    var certified = 0;
    final initial = DateTime.utc(2026, 11, 18).millisecondsSinceEpoch;
    await expectLater(
      RangeOlderPageScanner.scan(
        cursorMs: initial,
        alreadyLoaded: 0,
        maxPages: 1,
        isCurrent: () => true,
        fetchVerified: (from, to) async {
          final page = List<MarketTick>.generate(6100,
              (i) => MarketTick(from + i, 3900 + i * .0001));
          page[6099] = MarketTick(to + 1, 3901);
          return page;
        },
        onVerifiedPage: (from, to, ticks) => certified++,
      ),
      throwsA(isA<MarketDataException>()),
    );
    expect(certified, 0,
        reason: 'No failed provider window is persisted as complete');
  });

  test('verified empty windows are certified without fabricating ticks',
      () async {
    final archived = <(int, int)>[];
    final initial = DateTime.utc(2026, 11, 18).millisecondsSinceEpoch;
    final result = await RangeOlderPageScanner.scan(
      cursorMs: initial, alreadyLoaded: 0, maxPages: 3,
      isCurrent: () => true,
      fetchVerified: (from, to) async => const <MarketTick>[],
      onVerifiedPage: (from, to, ticks) {
        expect(ticks, isEmpty);
        archived.add((from, to));
      },
    );
    expect(result!.ticks, isEmpty);
    expect(result.emptyWindows, 3);
    expect(archived, hasLength(3));
    for (var i = 1; i < archived.length; i++) {
      expect(archived[i].$2, archived[i - 1].$1 - 1);
    }
  });

  test('stale account never receives verified-page archive callback',
      () async {
    var active = true;
    var notified = false;
    final initial = DateTime.utc(2026, 11, 18).millisecondsSinceEpoch;
    final result = await RangeOlderPageScanner.scan(
      cursorMs: initial,
      alreadyLoaded: 0,
      isCurrent: () => active,
      fetchVerified: (from, to) async {
        active = false;
        return [MarketTick(from, 3900)];
      },
      onVerifiedPage: (_, __, ___) => notified = true,
    );
    expect(result, isNull);
    expect(notified, isFalse);
  });
}
