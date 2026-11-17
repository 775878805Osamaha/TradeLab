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
