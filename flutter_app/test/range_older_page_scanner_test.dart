import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_older_page.dart';
import 'package:tradelab_flutter/data/range_older_page_scanner.dart';

void main() {
  const step = Duration(hours: 12).inMilliseconds;
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
}
