import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/ctrader_older_candle_pager.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  const lookback = Duration(minutes: 15);
  const span = 15 * 60 * 1000;
  final end = DateTime.utc(2026, 11, 12, 16).millisecondsSinceEpoch;
  const candle = TradeCandle(100, 102, 99, 101);

  test('automatically crosses quiet cTrader sessions with exact exclusive cursor',
      () async {
    final requested = <int>[];
    final result = await CTraderOlderCandlePager.load(
      cursorMs: end,
      lookback: lookback,
      fetch: (before) async {
        requested.add(before.millisecondsSinceEpoch);
        if (requested.length < 4) return const <MarketBar>[];
        return [MarketBar(before.millisecondsSinceEpoch - 60000, candle)];
      },
      isCurrent: () => true,
    );
    expect(result, isNotNull);
    expect(requested, [
      end - 1,
      end - span - 2,
      end - 2 * span - 3,
      end - 3 * span - 4,
    ]);
    expect(result!.quietWindows, 3);
    expect(result.bars, hasLength(1));
    expect(result.bars.single.timestamp, end - 3 * span - 4 - 60000);
    // The caller commits actual provider timestamps, never inferred gaps.
    expect(result.nextCursorMs, end - 3 * (span + 1));
  });

  test('quiet backfill has a hard five-page bound and resumes without overlap',
      () async {
    final requested = <int>[];
    final first = await CTraderOlderCandlePager.load(
      cursorMs: end,
      lookback: lookback,
      fetch: (before) async {
        requested.add(before.millisecondsSinceEpoch);
        return const <MarketBar>[];
      },
      isCurrent: () => true,
    );
    expect(first, isNotNull);
    expect(first!.bars, isEmpty);
    expect(first.quietWindows, 5);
    expect(requested, hasLength(5));
    expect(first.nextCursorMs, end - 5 * (span + 1));

    final secondRequested = <int>[];
    await CTraderOlderCandlePager.load(
      cursorMs: first.nextCursorMs,
      lookback: lookback,
      maxPages: 1,
      fetch: (before) async {
        secondRequested.add(before.millisecondsSinceEpoch);
        return const <MarketBar>[];
      },
      isCurrent: () => true,
    );
    expect(secondRequested.single, requested.last - span - 1);
  });

  test('cancels immediately when chart account or symbol changes', () async {
    var active = true;
    var requests = 0;
    final response = await CTraderOlderCandlePager.load(
      cursorMs: end,
      lookback: lookback,
      fetch: (_) async {
        requests++;
        active = false; // An account switch while broker request was running.
        return [MarketBar(end - 1000, candle)];
      },
      isCurrent: () => active,
    );
    expect(response, isNull);
    expect(requests, 1);
  });

  test('never starts a broker request after cancellation', () async {
    var requested = false;
    final response = await CTraderOlderCandlePager.load(
      cursorMs: end,
      lookback: lookback,
      fetch: (_) async {
        requested = true;
        return const <MarketBar>[];
      },
      isCurrent: () => false,
    );
    expect(response, isNull);
    expect(requested, isFalse);
  });

  test('broker failures propagate rather than inventing old candles', () async {
    await expectLater(
      CTraderOlderCandlePager.load(
        cursorMs: end,
        lookback: lookback,
        fetch: (_) => Future<List<MarketBar>>.error(StateError('provider')),
        isCurrent: () => true,
      ),
      throwsStateError,
    );
  });

  test('invalid windows and unbounded scanning are rejected', () async {
    Future<List<MarketBar>> load(_) async => const <MarketBar>[];
    for (final limit in [0, 6]) {
      await expectLater(
        CTraderOlderCandlePager.load(
          cursorMs: end, lookback: lookback, fetch: load,
          isCurrent: () => true, maxPages: limit,
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      CTraderOlderCandlePager.load(
        cursorMs: 0, lookback: lookback, fetch: load,
        isCurrent: () => true,
      ),
      throwsArgumentError,
    );
  });
}
