import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_bar_timeline.dart';
import 'package:tradelab_flutter/data/range_size_reuse.dart';

void main() {
  const ticks = <MarketTick>[
    MarketTick(1763730000000, 100.0),
    MarketTick(1763730000001, 100.5),
    MarketTick(1763730000002, 101.0),
    MarketTick(1763730000003, 102.0),
    MarketTick(1763730000004, 101.5),
    MarketTick(1763730000005, 104.0),
  ];

  test('existing real BID history can rebuild multiple sizes without reload',
      () async {
    final source = List<MarketTick>.unmodifiable(ticks);
    final first = RangeBarTimeline.build(source, .5);
    expect(RangeSizeReuse.canRebuild(
        verifiedTicks: source, previousTimeline: first,
        pointSize: .01, nextRangePoints: 100,
        sourceReady: true), isTrue);
    final changed = await RangeSizeReuse.rebuild(
        verifiedTicks: source, previousTimeline: first,
        pointSize: .01, nextRangePoints: 100);
    expect(changed.priceDistance, 1);
    expect(changed.closedBarCount, lessThan(first.closedBarCount));
    expect(changed.endTickIndices.last, source.length - 1);
    expect(changed.endTimestamps.last, source.last.timestamp);
    expect(changed.bars.last.close, source.last.bid);
    expect(source, orderedEquals(ticks));
    final again = await RangeSizeReuse.rebuild(
        verifiedTicks: source, previousTimeline: changed,
        pointSize: .01, nextRangePoints: 50);
    expect(again.priceDistance, .5);
    expect(again.bars, hasLength(first.bars.length));
    for (var i = 0; i < first.bars.length; i++) {
      expect(again.bars[i].open, first.bars[i].open);
      expect(again.bars[i].high, first.bars[i].high);
      expect(again.bars[i].low, first.bars[i].low);
      expect(again.bars[i].close, first.bars[i].close);
      expect(again.endTickIndices[i], first.endTickIndices[i]);
    }
  });

  test('cannot reuse unverified or mismatched BID timeline', () {
    final prior = RangeBarTimeline.build(ticks, .5);
    bool eligible(List<MarketTick> source, {bool ready = true}) =>
        RangeSizeReuse.canRebuild(
          verifiedTicks: source, previousTimeline: prior,
          pointSize: .01, nextRangePoints: 100,
          sourceReady: ready,
        );
    expect(eligible(ticks), isTrue);
    expect(eligible(ticks, ready: false), isFalse);
    expect(eligible(ticks.sublist(1)), isFalse);
    expect(eligible(ticks.sublist(0, ticks.length - 1)), isFalse);
    expect(eligible(const <MarketTick>[]), isFalse);
    expect(eligible(<MarketTick>[
      ...ticks.sublist(0, ticks.length - 1),
      MarketTick(ticks.last.timestamp, 999),
    ]), isFalse);
    expect(RangeSizeReuse.canRebuild(
        verifiedTicks: ticks, previousTimeline: null,
        pointSize: .01, nextRangePoints: 100,
        sourceReady: true), isFalse);
    expect(RangeSizeReuse.canRebuild(
        verifiedTicks: ticks, previousTimeline: prior,
        pointSize: 0, nextRangePoints: 100,
        sourceReady: true), isFalse);
    expect(RangeSizeReuse.canRebuild(
        verifiedTicks: ticks, previousTimeline: prior,
        pointSize: .01, nextRangePoints: 0,
        sourceReady: true), isFalse);
    expect(() => RangeSizeReuse.rebuild(
        verifiedTicks: ticks.sublist(1), previousTimeline: prior,
        pointSize: .01, nextRangePoints: 100), throwsStateError);
  });

  test('Replay only executes completed Range bars after local size change',
      () async {
    final old = RangeBarTimeline.build(ticks, .5);
    final next = await RangeSizeReuse.rebuild(
        verifiedTicks: ticks, previousTimeline: old,
        pointSize: .01, nextRangePoints: 100);
    expect(next.visibleClosedBarsThroughTick(ticks.length - 1),
        next.closedBarCount);
    expect(next.visibleClosedBarsThroughTick(-1), 0);
    expect(next.bars.length, next.closedBarCount + 1,
      reason: 'The last real BID candle is still forming, not a Replay fill');
  });
}
