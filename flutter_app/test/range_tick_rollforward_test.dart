import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_tick_rollforward.dart';
import 'package:tradelab_flutter/data/range_tick_store.dart';

void main() {
  const sixDays = Duration(days: 6);
  final anchor = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;
  final previous = VerifiedBidWindow(
    fromMs: anchor,
    toMs: anchor + sixDays.inMilliseconds,
    ticks: [
      MarketTick(anchor + 100, 2000),
      MarketTick(anchor + 100, 2001),
      MarketTick(anchor + const Duration(days: 2).inMilliseconds, 2002),
      MarketTick(anchor + sixDays.inMilliseconds, 2003),
    ],
  );

  test('roll forward six-day Range window without repeating old BID ticks', () {
    final toMs = previous.toMs + const Duration(hours: 1).inMilliseconds;
    final fromMs = toMs - sixDays.inMilliseconds;
    final suffix = [
      MarketTick(previous.toMs + 1, 2004),
      MarketTick(previous.toMs + 1, 2004.1),
      MarketTick(toMs, 2004.2),
    ];
    final merged = RangeTickRollforward.merge(
      cached: previous, newTicks: suffix,
      newFromMs: fromMs, newToMs: toMs,
    );
    // Discard old prices before the new rolling window start.
    expect(merged.map((tick) => tick.bid).toList(),
        [2002, 2003, 2004, 2004.1, 2004.2]);
    expect(merged.map((tick) => tick.timestamp).toList(),
        [previous.ticks[2].timestamp, previous.toMs,
         previous.toMs + 1, previous.toMs + 1, toMs]);
  });

  test('empty, verified increment retains the last known BID events', () {
    final toMs = previous.toMs + const Duration(minutes: 3).inMilliseconds;
    final merged = RangeTickRollforward.merge(
      cached: previous, newTicks: const <MarketTick>[],
      newFromMs: toMs - sixDays.inMilliseconds, newToMs: toMs,
    );
    expect(merged.map((tick) => tick.bid).toList(), [2002, 2003]);
  });

  test('rejects overlapping suffix even when boundary has same-ms ticks', () {
    final toMs = previous.toMs + 300000;
    expect(() => RangeTickRollforward.merge(
      cached: previous,
      newTicks: [MarketTick(previous.toMs, 9999)],
      newFromMs: toMs - sixDays.inMilliseconds, newToMs: toMs,
    ), throwsArgumentError);
  });

  test('rejects out-of-order and invalid broker suffix prices', () {
    final toMs = previous.toMs + 300000;
    final fromMs = toMs - sixDays.inMilliseconds;
    expect(() => RangeTickRollforward.merge(
      cached: previous,
      newTicks: [
        MarketTick(previous.toMs + 100, 2004),
        MarketTick(previous.toMs + 99, 2005),
      ],
      newFromMs: fromMs, newToMs: toMs,
    ), throwsArgumentError);
    expect(() => RangeTickRollforward.merge(
      cached: previous,
      newTicks: [MarketTick(previous.toMs + 100, double.nan)],
      newFromMs: fromMs, newToMs: toMs,
    ), throwsArgumentError);
  });

  test('does not stitch history when cached six-day coverage has a gap', () {
    final toMs = previous.toMs + const Duration(days: 7).inMilliseconds;
    expect(() => RangeTickRollforward.merge(
      cached: previous,
      newTicks: const <MarketTick>[],
      newFromMs: toMs - sixDays.inMilliseconds, newToMs: toMs,
    ), throwsArgumentError);
  });

  test('does not alter input tick arrays', () {
    final toMs = previous.toMs + const Duration(minutes: 3).inMilliseconds;
    final suffix = [MarketTick(previous.toMs + 1, 2010)];
    RangeTickRollforward.merge(
      cached: previous, newTicks: suffix,
      newFromMs: toMs - sixDays.inMilliseconds, newToMs: toMs,
    );
    expect(previous.ticks, hasLength(4));
    expect(suffix, hasLength(1));
  });
}
