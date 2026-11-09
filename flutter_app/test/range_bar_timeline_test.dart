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
    expect(timeline.visibleBarsThroughTick(-1), 0);
    expect(timeline.visibleBarsThroughTick(0), 0);
    expect(timeline.visibleBarsThroughTick(1), 2);
    expect(timeline.visibleBarsThroughTick(2), 2);
    expect(timeline.visibleBarsThroughTick(3), 3);
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

  test('empty tick window does not invent Range bars', () {
    final timeline = RangeBarTimeline.build(const <MarketTick>[], 1);
    expect(timeline.bars, isEmpty);
    expect(timeline.endTickIndices, isEmpty);
    expect(timeline.visibleBarsThroughTick(100), 0);
  });
}
