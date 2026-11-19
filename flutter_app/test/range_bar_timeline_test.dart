import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_bar_timeline.dart';

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
}
