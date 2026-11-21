import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_tick_rollforward.dart';
import 'package:tradelab_flutter/data/range_tick_store.dart';

class _MeasuredBidWindow extends ListBase<MarketTick> {
  _MeasuredBidWindow(this.source);
  final List<MarketTick> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Cached BID events are source-verified');

  @override
  MarketTick operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, MarketTick value) =>
      throw UnsupportedError('Cached BID events are source-verified');
}

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

  test('120k BID window skips obsolete history in logarithmic source reads',
      () {
    const start = 1700000000000;
    const sixDayMs = 6 * 24 * 60 * 60 * 1000;
    final source = List<MarketTick>.generate(120000, (i) =>
        MarketTick(start + i * 4320, 3900 + i * .0001),
        growable: false);
    final measured = _MeasuredBidWindow(source);
    final window = VerifiedBidWindow(
      fromMs: start, toMs: start + sixDayMs, ticks: measured);
    final result = RangeTickRollforward.merge(
      cached: window, newTicks: const <MarketTick>[],
      newFromMs: window.toMs, newToMs: window.toMs + sixDayMs);
    expect(result, isEmpty);
    expect(measured.reads, lessThan(30),
        reason: 'Skip 120k obsolete BID events without a linear scan');
    expect(source, hasLength(120000));
  });

  test('rolling BID window retains all same-millisecond boundary events', () {
    const start = 1700000000000;
    const sixDayMs = 6 * 24 * 60 * 60 * 1000;
    final source = <MarketTick>[
      MarketTick(start, 100),
      MarketTick(start + 1000, 101),
      MarketTick(start + 1000, 102),
      MarketTick(start + 1000, 103),
      MarketTick(start + 3000, 104),
    ];
    final previous = VerifiedBidWindow(
      fromMs: start, toMs: start + sixDayMs, ticks: source);
    final nextToMs = previous.toMs + 1000;
    final merged = RangeTickRollforward.merge(
      cached: previous,
      newTicks: [MarketTick(previous.toMs + 1, 105)],
      newFromMs: nextToMs - sixDayMs, newToMs: nextToMs);
    expect(merged.map((tick) => tick.bid), [101, 102, 103, 104, 105]);
    expect(merged[0], same(source[1]));
    expect(merged[2], same(source[3]));
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
