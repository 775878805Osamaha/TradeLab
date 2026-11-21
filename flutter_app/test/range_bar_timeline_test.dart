import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_bar_timeline.dart';
import 'package:tradelab_flutter/data/range_bar_builder.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

/// Refuse oversized provider requests without materializing million-row BID
/// arrays or even attempting to access a tick on the UI isolate.
class _UnmaterializedHugeBidWindow extends ListBase<MarketTick> {
  @override
  int get length => RangeBarTimeline.maxSourceTicks + 1;

  @override
  set length(int value) =>
      throw UnsupportedError('Only verified source windows can be published');

  @override
  MarketTick operator [](int index) =>
      throw StateError('Unbounded source was read before rejecting its size');

  @override
  void operator []=(int index, MarketTick value) =>
      throw UnsupportedError('Only verified source windows can be published');
}

void main() {
  test('Range bars are tied to the originating BID event, including jumps', () {
    final ticks = [
      MarketTick(100, 100),
      MarketTick(101, 102.4),
      MarketTick(102, 102.8),
      MarketTick(103, 102),
    ];
    final timeline = RangeBarTimeline.build(ticks, 1);
    expect(timeline.bars, hasLength(3));
    expect(timeline.endTickIndices, [1, 1, 3]);
    // A price gap may close multiple bars on one *real* BID event; do not
    // manufacture different clock times for the extra price-based bars.
    expect(timeline.endTimestamps, [101, 101, 103]);
    expect(timeline.visibleBarsThroughTick(-1), 0);
    expect(timeline.visibleBarsThroughTick(0), 0);
    expect(timeline.visibleBarsThroughTick(1), 2);
    expect(timeline.visibleBarsThroughTick(2), 2);
    expect(timeline.visibleBarsThroughTick(3), 3);
    // The trailing bar is the still-forming Range snapshot, not executable.
    expect(timeline.closedBarCount, 2);
    expect(timeline.visibleClosedBarsThroughTick(3), 2);
    expect(timeline.visibleClosedBarsThroughTick(1), 2);
  });

  test('published historical Range timeline cannot be edited by consumers',
      () async {
    const source = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 102.5),
      MarketTick(102, 101.5),
    ];
    final direct = RangeBarTimeline.build(source, 1);
    void assertReadOnly(RangeBarTimeline timeline) {
      final first = timeline.bars.first;
      final firstEvent = timeline.endTickIndices.first;
      final firstUtc = timeline.endTimestamps.first;
      expect(() => timeline.bars.add(first), throwsUnsupportedError);
      expect(() => timeline.bars[0] = first, throwsUnsupportedError);
      expect(() => timeline.bars.clear(), throwsUnsupportedError);
      expect(() => timeline.endTickIndices.add(100), throwsUnsupportedError);
      expect(() => timeline.endTickIndices[0] = 999,
          throwsUnsupportedError);
      expect(() => timeline.endTimestamps.removeLast(),
          throwsUnsupportedError);
      expect(() => timeline.endTimestamps[0] = -1,
          throwsUnsupportedError);
      expect(timeline.bars.first, first);
      expect(timeline.endTickIndices.first, firstEvent);
      expect(timeline.endTimestamps.first, firstUtc);
      expect(timeline.visibleClosedBarsThroughTick(1), 2);
    }
    assertReadOnly(direct);
    // Prepend has to use the identical protected publishing path, including
    // the actual source-event ordinal carried into Replay.
    final prepended = await RangeBarTimeline.prependAndBuildAsync(
      olderTicks: const [MarketTick(90, 99)],
      currentTicks: source,
      priceDistance: 1,
    );
    assertReadOnly(prepended.timeline);
    expect(prepended.timeline.endTickIndices.first, 1);
    expect(direct.endTickIndices.first, 1);
    expect(source.length, 3);
  });

  test('background-built 6k BID Range snapshot is read-only after isolate',
      () async {
    final ticks = List<MarketTick>.generate(6001, (i) =>
        MarketTick(1700000000000 + i, 100 + (i % 7) * .3));
    final timeline = await RangeBarTimeline.buildAsync(ticks, 1);
    expect(timeline.bars, isNotEmpty);
    final baseline = timeline.closedBarCount;
    expect(() => timeline.bars.add(timeline.bars.first),
        throwsUnsupportedError);
    expect(() => timeline.endTickIndices[0] = 777,
        throwsUnsupportedError);
    expect(() => timeline.endTimestamps[0] = 0,
        throwsUnsupportedError);
    expect(timeline.closedBarCount, baseline);
    expect(timeline.endTickIndices.last, ticks.length - 1);
    expect(timeline.endTimestamps.last, ticks.last.timestamp);
  });

  test('Range timeline rejects reversed BID timestamps without Replay leak',
      () async {
    final reversed = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(102, 101),
      MarketTick(101, 102),
    ];
    expect(() => RangeBarTimeline.build(reversed, 1),
        throwsA(isA<MarketDataException>()));
    await expectLater(RangeBarTimeline.buildAsync(reversed, 1),
        throwsA(isA<MarketDataException>()));
    expect(() => RangeBarTimeline.build(
        [MarketTick(-1, 100)], 1),
        throwsA(isA<MarketDataException>()));
    final sameMs = RangeBarTimeline.build([
      MarketTick(100, 100),
      MarketTick(100, 101),
      MarketTick(100, 102),
    ], 1);
    expect(sameMs.endTimestamps.every((ms) => ms == 100), isTrue);
    expect(sameMs.closedBarCount, 2);
    expect(sameMs.endTickIndices.take(2), [1, 2],
        reason: 'Same-ms BID events preserve original ordinal source order');
  });

  test('Range limits cap total closed bars before any Replay is published',
      () async {
    final ticks = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 103),
    ];
    final withinBudget =
        RangeBarTimeline.build(ticks, 1, closedBarLimit: 3);
    expect(withinBudget.closedBarCount, 3);
    expect(withinBudget.bars.last.close, 103);
    expect(withinBudget.visibleClosedBarsThroughTick(0), 0);
    expect(withinBudget.visibleClosedBarsThroughTick(1), 3);
    expect(() => RangeBarTimeline.build(
        ticks, 1, closedBarLimit: 2),
        throwsA(isA<MarketDataException>()));
    await expectLater(
        RangeBarTimeline.buildAsync(
            ticks, 1, closedBarLimit: 2),
        throwsA(isA<MarketDataException>()),
    );
    expect(ticks.map((t) => t.timestamp), [100, 101],
        reason: 'Failing a build must not change authentic source ticks');
  });

  test('older BID prepend obeys identical Range bar memory ceiling',
      () async {
    final older = <MarketTick>[MarketTick(90, 100)];
    final current = <MarketTick>[MarketTick(100, 104)];
    final permitted = await RangeBarTimeline.prependAndBuildAsync(
      olderTicks: older, currentTicks: current,
      priceDistance: 1, closedBarLimit: 4,
    );
    expect(permitted.timeline.closedBarCount, 4);
    expect(permitted.timeline.endTickIndices.take(4), [1, 1, 1, 1]);
    await expectLater(
      RangeBarTimeline.prependAndBuildAsync(
        olderTicks: older, currentTicks: current,
        priceDistance: 1, closedBarLimit: 3,
      ),
      throwsA(isA<MarketDataException>()),
    );
    expect(older.single.timestamp, 90);
    expect(current.single.timestamp, 100);
  });

  test('one million BID cap rejects giant source before reading any tick',
      () async {
    final huge = _UnmaterializedHugeBidWindow();
    expect(() => RangeBarTimeline.build(huge, 1),
        throwsA(isA<MarketDataException>()));
    await expectLater(
      RangeBarTimeline.buildAsync(huge, 1),
      throwsA(isA<MarketDataException>()),
    );
    await expectLater(
      RangeBarTimeline.prependAndBuildAsync(
        olderTicks: huge,
        currentTicks: const <MarketTick>[],
        priceDistance: 1,
      ),
      throwsA(isA<MarketDataException>()),
    );
    expect(() => RangeBarTimeline.build(
      const <MarketTick>[], 1, closedBarLimit: 0),
      throwsArgumentError);
    expect(() => RangeBarTimeline.build(
      const <MarketTick>[], 1,
      closedBarLimit: RangeBarTimeline.maxClosedBarCount + 1),
      throwsArgumentError);
  });

  test('live Range append equals complete source rebuild after 6200 BID ticks',
      () async {
    const start = 1700000000000;
    final old = List<MarketTick>.generate(6200, (i) =>
        MarketTick(start + i ~/ 2,
            3900 + (i % 9) * .13 + (i % 5) * .02),
        growable: false);
    final suffix = List<MarketTick>.generate(37, (i) =>
        MarketTick(old.last.timestamp + i ~/ 3,
            3901 + (i % 11) * .15 + (i % 3) * .04),
        growable: false);
    final prior = RangeBarTimeline.build(old, .5);
    final next = await RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: old, currentTimeline: prior,
      verifiedSuffix: suffix, priceDistance: .5,
    );
    final complete = RangeBarTimeline.build([...old, ...suffix], .5);
    expect(next.timeline.closedBarCount, complete.closedBarCount);
    expect(next.timeline.endTickIndices, complete.endTickIndices);
    expect(next.timeline.endTimestamps, complete.endTimestamps);
    expect(next.timeline.bars.length, complete.bars.length);
    for (var i = 0; i < complete.bars.length; i++) {
      final a = next.timeline.bars[i], b = complete.bars[i];
      expect((a.open, a.high, a.low, a.close),
          (b.open, b.high, b.low, b.close));
    }
    expect(next.ticks.map((t) => t.timestamp),
      [...old, ...suffix].map((t) => t.timestamp));
    expect(() => next.ticks.add(const MarketTick(999, 2)),
        throwsUnsupportedError);
    expect(() => next.timeline.bars.add(
        const TradeCandle(1, 2, 1, 2)), throwsUnsupportedError);
    expect(next.timeline.visibleClosedBarsThroughTick(old.length - 1),
        prior.closedBarCount,
        reason: 'New broker events must not close bars in older Replay');
    expect(old.length, 6200);
    expect(prior.endTickIndices.last, old.length - 1);
  });

  test('live Range same-ms events and tick gaps retain exact source ordinal',
      () async {
    const old = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(100, 101),
      MarketTick(101, 101.1),
    ];
    const extra = <MarketTick>[
      MarketTick(101, 101.8),
      MarketTick(101, 102.5),
      MarketTick(105, 103.6),
    ];
    final initial = RangeBarTimeline.build(old, 1);
    final appended = await RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: old, currentTimeline: initial,
      verifiedSuffix: extra, priceDistance: 1);
    final complete = RangeBarTimeline.build([...old, ...extra], 1);
    expect(appended.timeline.endTickIndices, complete.endTickIndices);
    expect(appended.timeline.endTimestamps, complete.endTimestamps);
    expect(appended.timeline.closedBarCount, complete.closedBarCount);
    expect(appended.timeline.bars.map((c) =>
        (c.open, c.high, c.low, c.close)),
        complete.bars.map((c) => (c.open, c.high, c.low, c.close)));
    expect(appended.timeline.visibleClosedBarsThroughTick(2),
        initial.closedBarCount);
    expect(appended.timeline.endTimestamps.last, 105);
  });

  test('live Range rejects stale snapshots with identical count and last UTC',
      () async {
    const current = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 102),
      MarketTick(101, 102.1),
    ];
    final published = RangeBarTimeline.build(current, 1);
    const suffix = <MarketTick>[MarketTick(102, 102.3)];
    Future<void> reject(List<MarketTick> source,
        RangeBarTimeline timeline) async {
      await expectLater(
        RangeBarTimeline.appendVerifiedSuffixAsync(
          currentTicks: source,
          currentTimeline: timeline,
          verifiedSuffix: suffix,
          priceDistance: 1,
        ),
        throwsA(isA<MarketDataException>()),
      );
    }

    // Same source length and final timestamp; first BID origin changed.
    await reject(const <MarketTick>[
      MarketTick(100, 100.5),
      MarketTick(101, 102),
      MarketTick(101, 102.1),
    ], published);

    // Same source length and final timestamp; last BID/unfinished close
    // changed, which would otherwise invent an incorrect Range continuation.
    await reject(const <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 102),
      MarketTick(101, 102.2),
    ], published);

    // Identical endpoints and event count, but the FIRST close belongs to
    // an earlier millisecond in the stale timeline.
    final staleFirstClose = RangeBarTimeline.build(const <MarketTick>[
      MarketTick(100, 100),
      MarketTick(100, 102),
      MarketTick(101, 102.1),
    ], 1);
    await reject(current, staleFirstClose);

    // Unchanged authentic BID source must still append correctly.
    final valid = await RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: current, currentTimeline: published,
      verifiedSuffix: suffix, priceDistance: 1);
    expect(valid.ticks, hasLength(4));
    expect(valid.timeline.endTickIndices.last, 3);
    expect(valid.timeline.bars.last.close, 102.3);
    expect(published.endTickIndices.last, 2);
  });

  test('live Range no-op keeps published immutable source list identity',
      () async {
    const old = <MarketTick>[
      MarketTick(100, 100), MarketTick(101, 102),
    ];
    final timeline = RangeBarTimeline.build(old, 1);
    final unchanged = await RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: old, currentTimeline: timeline,
      verifiedSuffix: const [], priceDistance: 1);
    expect(identical(unchanged.ticks, old), isTrue);
    expect(identical(unchanged.timeline, timeline), isTrue);
  });

  test('live Range over-budget, malformed and stale timelines fail closed',
      () async {
    const old = <MarketTick>[
      MarketTick(100, 100), MarketTick(101, 101),
    ];
    final prior = RangeBarTimeline.build(old, 1);
    await expectLater(RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: old, currentTimeline: prior,
      verifiedSuffix: const [MarketTick(102, 105)],
      priceDistance: 1, closedBarLimit: 2),
      throwsA(isA<MarketDataException>()));
    await expectLater(RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: old, currentTimeline: prior,
      verifiedSuffix: const [MarketTick(99, 101)],
      priceDistance: 1), throwsA(isA<MarketDataException>()));
    await expectLater(RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: old, currentTimeline: prior,
      verifiedSuffix: const [MarketTick(102, -1)],
      priceDistance: 1), throwsA(isA<MarketDataException>()));
    await expectLater(RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: const [MarketTick(100, 100)],
      currentTimeline: prior,
      verifiedSuffix: const [MarketTick(102, 104)],
      priceDistance: 1), throwsA(isA<MarketDataException>()));
    expect(prior.closedBarCount, 1);
    expect(prior.bars.last.close, 101);
  });

  test('historical Range rejects huge BID jumps at the exact bar budget',
      () async {
    const ticks = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 102),
      MarketTick(102, 40102),
    ];
    final validPrefix = RangeBarTimeline.build(
        ticks.take(2).toList(), 1, closedBarLimit: 2);
    expect(validPrefix.closedBarCount, 2);
    expect(validPrefix.endTickIndices.take(2), [1, 1]);

    // A 40k-bar source jump cannot produce a partial public Replay timeline.
    expect(() => RangeBarTimeline.build(ticks, 1, closedBarLimit: 3),
        throwsA(isA<MarketDataException>()));
    await expectLater(
      RangeBarTimeline.buildAsync(ticks, 1, closedBarLimit: 3),
      throwsA(isA<MarketDataException>()),
    );
    expect(validPrefix.closedBarCount, 2);
    expect(validPrefix.bars.last.close, 102);
    expect(ticks, hasLength(3));
  });

  test('live Range enforces remaining closed bars before huge BID expansion',
      () async {
    const old = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 102),
    ];
    final existing = RangeBarTimeline.build(old, 1);
    const huge = <MarketTick>[MarketTick(102, 40102)];
    await expectLater(RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: old, currentTimeline: existing,
      verifiedSuffix: huge, priceDistance: 1, closedBarLimit: 3,
    ), throwsA(isA<MarketDataException>()));
    expect(existing.closedBarCount, 2);
    expect(existing.endTickIndices, [1, 1, 1]);
    expect(old.last.bid, 102);
  });

  test('live Range exact budget and forming-only update preserve source',
      () async {
    const old = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 102),
    ];
    final timeline = RangeBarTimeline.build(old, 1);
    final appended = await RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: old, currentTimeline: timeline,
      verifiedSuffix: const <MarketTick>[MarketTick(102, 102.5)],
      priceDistance: 1, closedBarLimit: 2,
    );
    expect(appended.timeline.closedBarCount, 2);
    expect(appended.timeline.bars.last.close, 102.5);
    expect(appended.timeline.endTickIndices.last, 2);
    expect(appended.timeline.visibleClosedBarsThroughTick(1), 2);
  });

  test('one authentic tick produces a forming bar but zero Replay bars', () {
    final timeline = RangeBarTimeline.build([MarketTick(100, 102)], 1);
    expect(timeline.bars, hasLength(1));
    expect(timeline.closedBarCount, 0);
    expect(timeline.visibleBarsThroughTick(0), 1);
    expect(timeline.visibleClosedBarsThroughTick(0), 0);
  });

  test('Replay cutoff remains at same source event when ticks prepend', () {
    final originalTicks = [
      MarketTick(100, 100),
      MarketTick(101, 102.4),
      MarketTick(102, 102.8),
      MarketTick(103, 102),
      MarketTick(104, 120), // Future jump must stay hidden.
    ];
    final original = RangeBarTimeline.build(originalTicks, 1);
    const visibleBars = 2;
    final lastVisibleTick = original.endTickIndices[visibleBars - 1];
    final prefix = [
      MarketTick(80, 98),
      MarketTick(81, 99),
      MarketTick(82, 100),
    ];
    final rebuilt = RangeBarTimeline.build([...prefix, ...originalTicks], 1);
    final safeVisible = rebuilt.visibleBarsThroughTick(
        prefix.length + lastVisibleTick);
    expect(safeVisible, greaterThan(0));
    expect(rebuilt.endTickIndices[safeVisible - 1],
        lessThanOrEqualTo(prefix.length + lastVisibleTick));
    if (safeVisible < rebuilt.bars.length) {
      expect(rebuilt.endTickIndices[safeVisible],
          greaterThan(prefix.length + lastVisibleTick));
    }
  });

  test('new Range origin can make every bar depend on future ticks', () {
    // The original close at timestamp 101 was safe to show in Replay.
    final old = RangeBarTimeline.build([
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(102, 102),
    ], 1);
    final cutoffTick = old.endTickIndices.first;
    expect(cutoffTick, 1);

    // Adding a preceding price changes the new Range origin to 100.5,
    // so the first close occurs at timestamp 102 (still in the future).
    final rebuilt = RangeBarTimeline.build([
      MarketTick(90, 100.5),
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(102, 102),
    ], 1);
    expect(rebuilt.visibleBarsThroughTick(1 + cutoffTick), 0);
    // The chart must NOT clamp this zero to one visible candle.
  });

  test('large Range history builds on background isolate identically',
      () async {
    final ticks = List<MarketTick>.generate(6001, (index) =>
        MarketTick(1700000000000 + index,
            1900 + (index % 17) * .13 + (index % 5) * .02));
    final synchronous = RangeBarTimeline.build(ticks, .5);
    final asyncResult = await RangeBarTimeline.buildAsync(ticks, .5);
    expect(asyncResult.endTickIndices, synchronous.endTickIndices);
    expect(asyncResult.endTimestamps, synchronous.endTimestamps);
    expect(asyncResult.bars.length, synchronous.bars.length);
    for (var index = 0; index < synchronous.bars.length; index++) {
      final expected = synchronous.bars[index];
      final actual = asyncResult.bars[index];
      expect(actual.open, expected.open);
      expect(actual.high, expected.high);
      expect(actual.low, expected.low);
      expect(actual.close, expected.close);
    }
  });

  test('older BID prepend preserves source order and strict Replay cutoff',
      () async {
    final current = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(102, 102),
    ];
    final older = <MarketTick>[MarketTick(90, 100.5)];
    final original = RangeBarTimeline.build(current, 1);
    final cutoffTick = original.endTickIndices.first;
    final rebuilt = await RangeBarTimeline.prependAndBuildAsync(
      olderTicks: older,
      currentTicks: current,
      priceDistance: 1,
    );
    final direct = RangeBarTimeline.build([...older, ...current], 1);
    expect(rebuilt.ticks.map((t) => t.timestamp), [90, 100, 101, 102]);
    expect(rebuilt.timeline.endTickIndices, direct.endTickIndices);
    expect(rebuilt.timeline.endTimestamps, direct.endTimestamps);
    expect(rebuilt.timeline.bars.length, direct.bars.length);
    expect(rebuilt.timeline.visibleBarsThroughTick(
        older.length + cutoffTick), 0,
        reason: 'Never reveal a Range bar closed by an unrevealed BID tick');
    expect(current.map((t) => t.timestamp), [100, 101, 102],
        reason: 'Existing broker history must not be modified by prepending');
    expect(() => rebuilt.ticks.add(MarketTick(103, 103)),
        throwsUnsupportedError);
    older.add(MarketTick(91, 999));
    expect(rebuilt.ticks.length, 4,
        reason: 'Old published BID snapshots cannot change with provider');
    await expectLater(
      RangeBarTimeline.prependAndBuildAsync(
        olderTicks: [MarketTick(100, 100)],
        currentTicks: current,
        priceDistance: 1,
      ),
      throwsArgumentError,
      reason: 'Overlapping same-ms source events require original ordering',
    );
  });

  test('large older BID prepend matches synchronous Range bars and events',
      () async {
    const start = 1700000000000;
    // Thousands of broker BID events, including identical timestamps inside
    // both pages. The boundary itself is disjoint by verified millisecond.
    final older = List<MarketTick>.generate(1300, (index) =>
        MarketTick(start + index ~/ 2,
            1900 + (index % 13) * .13 + (index % 3) * .02));
    final current = List<MarketTick>.generate(5101, (index) =>
        MarketTick(start + 1000 + index ~/ 2,
            1901 + (index % 17) * .13 + (index % 5) * .02));
    final expectedTicks = [...older, ...current];
    final direct = RangeBarTimeline.build(expectedTicks, .5);
    final rebuilt = await RangeBarTimeline.prependAndBuildAsync(
      olderTicks: older,
      currentTicks: current,
      priceDistance: .5,
    );
    expect(rebuilt.ticks.length, expectedTicks.length);
    for (var i = 0; i < expectedTicks.length; i++) {
      expect(rebuilt.ticks[i].timestamp, expectedTicks[i].timestamp);
      expect(rebuilt.ticks[i].bid, expectedTicks[i].bid);
    }
    expect(rebuilt.timeline.endTickIndices, direct.endTickIndices);
    expect(rebuilt.timeline.endTimestamps, direct.endTimestamps);
    expect(rebuilt.timeline.bars.length, direct.bars.length);
    for (var i = 0; i < direct.bars.length; i++) {
      final a = direct.bars[i];
      final b = rebuilt.timeline.bars[i];
      expect(b.open, a.open);
      expect(b.high, a.high);
      expect(b.low, a.low);
      expect(b.close, a.close);
    }
    expect(rebuilt.timeline.closedBarCount, direct.closedBarCount);
    final cutoff = older.length + 212;
    final revealed = rebuilt.timeline.visibleClosedBarsThroughTick(cutoff);
    expect(revealed, lessThanOrEqualTo(rebuilt.timeline.closedBarCount));
    if (revealed > 0) {
      expect(rebuilt.timeline.endTickIndices[revealed - 1],
          lessThanOrEqualTo(cutoff));
    }
  });

  test('sparse BID gaps are scheduled off the UI isolate by bar work',
      () async {
    final quiet = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 100.2),
      MarketTick(102, 100.3),
    ];
    expect(RangeBarTimeline.shouldBuildInBackground(quiet, 1), isFalse);
    final jumping = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 4200),
    ];
    expect(jumping.length, lessThan(5000));
    expect(RangeBarTimeline.shouldBuildInBackground(jumping, 1), isTrue,
        reason: 'One authentic tick may close thousands of Range bars');

    final synchronous = RangeBarTimeline.build(jumping, 1);
    final asynchronous = await RangeBarTimeline.buildAsync(jumping, 1);
    expect(asynchronous.closedBarCount, 4100);
    expect(asynchronous.endTickIndices, synchronous.endTickIndices);
    expect(asynchronous.endTimestamps, synchronous.endTimestamps);
    expect(asynchronous.endTimestamps.take(asynchronous.closedBarCount)
        .every((ms) => ms == 101), isTrue,
        reason: 'Do not invent separate timestamps for a single BID jump');
    for (var i = 0; i < synchronous.bars.length; i++) {
      expect(asynchronous.bars[i].open, synchronous.bars[i].open);
      expect(asynchronous.bars[i].high, synchronous.bars[i].high);
      expect(asynchronous.bars[i].low, synchronous.bars[i].low);
      expect(asynchronous.bars[i].close, synchronous.bars[i].close);
    }
  });

  test('sparse older BID prepend uses same price-work offload policy',
      () async {
    final older = <MarketTick>[MarketTick(90, 100)];
    final current = <MarketTick>[MarketTick(100, 4200)];
    expect(RangeBarTimeline.shouldBuildInBackground(
      older.followedBy(current), 1), isTrue);
    final expected = RangeBarTimeline.build([...older, ...current], 1);
    final result = await RangeBarTimeline.prependAndBuildAsync(
      olderTicks: older,
      currentTicks: current,
      priceDistance: 1,
    );
    expect(result.ticks.map((tick) => tick.timestamp), [90, 100]);
    expect(result.timeline.endTickIndices, expected.endTickIndices);
    expect(result.timeline.endTimestamps, expected.endTimestamps);
    expect(result.timeline.closedBarCount, expected.closedBarCount);
    expect(result.timeline.visibleClosedBarsThroughTick(0), 0,
        reason: 'First tick does not reveal future jumping price');
  });

  test('empty tick window does not invent Range bars', () {
    final timeline = RangeBarTimeline.build(const <MarketTick>[], 1);
    expect(timeline.bars, isEmpty);
    expect(timeline.endTickIndices, isEmpty);
    expect(timeline.endTimestamps, isEmpty);
    expect(timeline.visibleBarsThroughTick(100), 0);
    expect(timeline.closedBarCount, 0);
    expect(timeline.visibleClosedBarsThroughTick(100), 0);
  });

  test('Range drawings rebase using BID event rather than candle shift', () {
    final originalTicks = [
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(102, 102),
      MarketTick(103, 103),
    ];
    final previous = RangeBarTimeline.build(originalTicks, 1);
    final prefix = [
      MarketTick(90, 100.5),
      MarketTick(91, 99.5),
      MarketTick(92, 98.5),
    ];
    final rebuilt = RangeBarTimeline.build([...prefix, ...originalTicks], 1);
    final oldBar = previous.endTickIndices.indexOf(2);
    final mapped = rebuilt.rebaseOldBarIndex(
      oldEndTickIndices: previous.endTickIndices,
      oldIndex: oldBar,
      prependedTicks: prefix.length,
      anchorPrice: previous.bars[oldBar].close,
    );
    expect(mapped, isNotNull);
    // No mapped bar can originate from ticks after the anchor market event.
    expect(rebuilt.endTickIndices[mapped!],
        lessThanOrEqualTo(prefix.length + previous.endTickIndices[oldBar]));
    expect(rebuilt.rebaseOldBarIndex(
      oldEndTickIndices: previous.endTickIndices,
      oldIndex: -1,
      prependedTicks: prefix.length,
      anchorPrice: 100,
    ), isNull);
  });

  test('Range drawing rebase never borrows an unrevealed future event', () {
    final previous = RangeBarTimeline.build([
      MarketTick(100, 100), MarketTick(101, 101), MarketTick(102, 102),
    ], 1);
    final rebuilt = RangeBarTimeline.build([
      MarketTick(90, 100.5),
      MarketTick(100, 100), MarketTick(101, 101), MarketTick(102, 102),
    ], 1);
    expect(rebuilt.rebaseOldBarIndex(
      oldEndTickIndices: previous.endTickIndices,
      oldIndex: 0,
      prependedTicks: 1,
      anchorPrice: 101,
    ), isNull);
  });

  test('Range Replay start stays tied to historical BID event after prepend', () {
    final oldTicks = [
      MarketTick(100, 100),
      MarketTick(101, 102.4),
      MarketTick(102, 102.8),
      MarketTick(103, 102),
      MarketTick(104, 120),
    ];
    final oldTimeline = RangeBarTimeline.build(oldTicks, 1);
    expect(oldTimeline.closedBarCount, greaterThanOrEqualTo(2));
    const selectedIndex = 1;
    final oldEvent = oldTimeline.endTickIndices[selectedIndex];
    final prefix = [
      MarketTick(90, 98),
      MarketTick(91, 99),
      MarketTick(92, 100),
    ];
    final newTimeline =
        RangeBarTimeline.build([...prefix, ...oldTicks], 1);
    final remapped = newTimeline.rebaseReplayStart(
      oldEndTickIndices: oldTimeline.endTickIndices,
      oldSelectedIndex: selectedIndex,
      prependedTicks: prefix.length,
    );
    expect(remapped, isNotNull);
    expect(remapped, lessThan(newTimeline.closedBarCount));
    expect(newTimeline.endTickIndices[remapped!],
        lessThanOrEqualTo(oldEvent + prefix.length),
        reason: 'Candidate must not require a BID event after old start');
  });

  test('Range Replay start fails closed when rebuilt bar needs future BID', () {
    final old = RangeBarTimeline.build([
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(102, 102),
    ], 1);
    final rebuilt = RangeBarTimeline.build([
      MarketTick(90, 100.5),
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(102, 102),
    ], 1);
    expect(rebuilt.rebaseReplayStart(
      oldEndTickIndices: old.endTickIndices,
      oldSelectedIndex: 0,
      prependedTicks: 1,
    ), isNull);
    expect(rebuilt.rebaseReplayStart(
      oldEndTickIndices: old.endTickIndices,
      oldSelectedIndex: -1,
      prependedTicks: 1,
    ), isNull);
  });

  test('Range Replay reset start follows its original BID event after older page',
      () {
    final original = RangeBarTimeline.build([
      MarketTick(100, 100),
      MarketTick(101, 102.4),
      MarketTick(102, 102.8),
      MarketTick(103, 102),
      MarketTick(104, 120),
    ], 1);
    const initialIndex = 0;
    final currentIndex = original.closedBarCount - 1;
    expect(currentIndex, greaterThan(initialIndex));
    final prepended = [
      MarketTick(90, 98), MarketTick(91, 99), MarketTick(92, 100),
    ];
    final rebuilt = RangeBarTimeline.build([
      ...prepended,
      MarketTick(100, 100),
      MarketTick(101, 102.4),
      MarketTick(102, 102.8),
      MarketTick(103, 102),
      MarketTick(104, 120),
    ], 1);
    final originalStartEvent = original.endTickIndices[initialIndex];
    final originalCurrentEvent = original.endTickIndices[currentIndex];
    final newStartIndex = rebuilt.rebaseReplayStart(
      oldEndTickIndices: original.endTickIndices,
      oldSelectedIndex: initialIndex,
      prependedTicks: prepended.length,
    );
    final newVisibleCount = rebuilt.visibleClosedBarsThroughTick(
        prepended.length + originalCurrentEvent);
    expect(newStartIndex, isNotNull);
    expect(newStartIndex! + 1, lessThanOrEqualTo(newVisibleCount),
        reason: 'Reset must never jump after current verified Replay cutoff');
    expect(rebuilt.endTickIndices[newStartIndex],
        lessThanOrEqualTo(prepended.length + originalStartEvent),
        reason: 'Rebased reset cannot depend on a future BID event');
  });

  test('Range Replay rejects rebuild when its start would need future BID',
      () {
    final original = RangeBarTimeline.build([
      MarketTick(100, 100), MarketTick(101, 101), MarketTick(102, 102),
    ], 1);
    final rebuilt = RangeBarTimeline.build([
      MarketTick(90, 100.5),
      MarketTick(100, 100), MarketTick(101, 101), MarketTick(102, 102),
    ], 1);
    expect(rebuilt.rebaseReplayStart(
      oldEndTickIndices: original.endTickIndices,
      oldSelectedIndex: 0,
      prependedTicks: 1,
    ), isNull,
      reason: 'Cannot reset to a candle that only closes after the old start');
  });

  test('120k BID events: sealed Range output matches independent builder OHLC',
      () async {
    const tickCount = 120000;
    const first = 1700000000000;
    final source = List<MarketTick>.generate(tickCount, (index) {
      final oscillation = (index % 37) * .12;
      return MarketTick(first + index ~/ 2, 3900.0 + oscillation);
    }, growable: false);
    final legacy = RangeBarBuilder(.5);
    final expectedEndTicks = <int>[];
    final expectedTimes = <int>[];
    for (var index = 0; index < source.length; index++) {
      final before = legacy.closedCount;
      legacy.appendBidTick(source[index].bid);
      for (var i = before; i < legacy.closedCount; i++) {
        expectedEndTicks.add(index);
        expectedTimes.add(source[index].timestamp);
      }
    }
    final expected = legacy.snapshot();
    expectedEndTicks.add(source.length - 1);
    expectedTimes.add(source.last.timestamp);
    final output = await RangeBarTimeline.buildAsync(source, .5);
    expect(output.endTickIndices, expectedEndTicks);
    expect(output.endTimestamps, expectedTimes);
    expect(output.bars, hasLength(expected.length));
    expect(output.closedBarCount, expected.length - 1);
    for (var index = 0; index < expected.length; index++) {
      final a = output.bars[index];
      final b = expected[index];
      expect((a.open, a.high, a.low, a.close),
          (b.open, b.high, b.low, b.close));
    }
    final cutoff = source.length ~/ 2;
    final visible = output.visibleClosedBarsThroughTick(cutoff);
    expect(visible, lessThanOrEqualTo(output.closedBarCount));
    if (visible > 0) {
      expect(output.endTickIndices[visible - 1], lessThanOrEqualTo(cutoff));
    }
    if (visible < output.closedBarCount) {
      expect(output.endTickIndices[visible], greaterThan(cutoff));
    }
    expect(source.first.timestamp, first);
    expect(source.last.timestamp, first + (tickCount - 1) ~/ 2);
  });

  test('forming Range bar remains non-executable with a one-tick history',
      () {
    final single = RangeBarTimeline.build([MarketTick(12345, 3900)], 1);
    expect(single.bars, hasLength(1));
    expect(single.closedBarCount, 0);
    expect(single.endTickIndices, [0]);
    expect(single.endTimestamps, [12345]);
    expect(single.visibleBarsThroughTick(0), 1);
    expect(single.visibleClosedBarsThroughTick(0), 0);
  });
}
