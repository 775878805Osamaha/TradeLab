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

  test('empty tick window does not invent Range bars', () {
    final timeline = RangeBarTimeline.build(const <MarketTick>[], 1);
    expect(timeline.bars, isEmpty);
    expect(timeline.endTickIndices, isEmpty);
    expect(timeline.visibleBarsThroughTick(100), 0);
  });
}
