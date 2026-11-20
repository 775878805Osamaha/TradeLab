import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_live_bid_delta.dart';
import 'package:tradelab_flutter/data/range_bar_timeline.dart';

void main() {
  test('inclusive cTrader page verifies same-ms ordinal then appends only new BID',
      () async {
    const original = <MarketTick>[
      MarketTick(1000, 3900),
      MarketTick(1001, 3901),
      MarketTick(1001, 3901),
      MarketTick(1001, 3901.5),
    ];
    const page = <MarketTick>[
      MarketTick(1001, 3901),
      MarketTick(1001, 3901),
      MarketTick(1001, 3901.5),
      MarketTick(1001, 3902),
      MarketTick(1001, 3902),
      MarketTick(1002, 3903),
    ];
    final suffix = await RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: original, brokerPage: page, toMs: 1002);
    expect(suffix.map((tick) => tick.timestamp),
        [1001, 1001, 1002]);
    expect(suffix.map((tick) => tick.bid), [3902, 3902, 3903]);
    expect(original.map((tick) => tick.bid),
        [3900, 3901, 3901, 3901.5],
        reason: 'Source order and original cached events never mutate');
    expect(() => suffix.add(const MarketTick(1003, 3999)),
        throwsUnsupportedError);
  });

  test('all-overlap live poll is a no-op, never a new market candle', () async {
    const original = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 101),
    ];
    final suffix = await RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: original,
      brokerPage: const [MarketTick(101, 101)],
      toMs: 105);
    expect(suffix, isEmpty);
  });

  test('missing, partial, wrong-price and reordered overlap fail closed',
      () async {
    const older = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(101, 102),
    ];
    for (final page in <List<MarketTick>>[
      <MarketTick>[],
      const [MarketTick(101, 101)],
      const [MarketTick(101, 101), MarketTick(101, 999)],
      const [MarketTick(101, 102), MarketTick(101, 101)],
      const [MarketTick(100, 100), MarketTick(101, 102)],
      const [MarketTick(101, 101), MarketTick(101, 102),
        MarketTick(103, 103), MarketTick(102, 102)],
      const [MarketTick(101, 101), MarketTick(101, 102),
        MarketTick(106, 106)],
    ]) {
      await expectLater(RangeLiveBidDelta.verifiedSuffixAsync(
        previouslyVerified: older,
        brokerPage: page, toMs: 105),
        throwsA(isA<MarketDataException>()),
        reason: 'Never silently skip or reorder authenticated source ticks');
    }
  });

  test('inclusive source update rebuilds exactly the same Range Replay timeline',
      () async {
    const previous = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 100.6),
      MarketTick(101, 101.3),
    ];
    const page = <MarketTick>[
      MarketTick(101, 100.6),
      MarketTick(101, 101.3),
      MarketTick(101, 102.6),
      MarketTick(102, 103.4),
    ];
    final prior = RangeBarTimeline.build(previous, 1);
    final suffix = await RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: previous, brokerPage: page, toMs: 102);
    final appended = await RangeBarTimeline.appendVerifiedSuffixAsync(
      currentTicks: previous, currentTimeline: prior,
      verifiedSuffix: suffix, priceDistance: 1);
    final direct = RangeBarTimeline.build([...previous, ...suffix], 1);
    expect(appended.timeline.endTickIndices, direct.endTickIndices);
    expect(appended.timeline.endTimestamps, direct.endTimestamps);
    expect(appended.timeline.bars.map((bar) =>
      (bar.open, bar.high, bar.low, bar.close)),
      direct.bars.map((bar) =>
      (bar.open, bar.high, bar.low, bar.close)));
    expect(appended.timeline.visibleClosedBarsThroughTick(2),
        prior.closedBarCount,
        reason: 'BID ticks newer than Replay cutoff must stay invisible');
    expect(appended.ticks.map((t) => t.timestamp),
        [100, 101, 101, 101, 102]);
  });

  test('6500-tick signed page offloads comparison without skipping same-ms ticks',
      () async {
    const old = <MarketTick>[
      MarketTick(1000, 100), MarketTick(1001, 101),
    ];
    final page = <MarketTick>[
      const MarketTick(1001, 101),
      for (var i = 0; i < 6500; i++)
        MarketTick(1002 + i, 100 + i * .01),
    ];
    final suffix = await RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: old, brokerPage: page, toMs: 7600);
    expect(suffix, hasLength(6500));
    expect(suffix.first.timestamp, 1002);
    expect(suffix.last.timestamp, 7501);
    expect(old, hasLength(2));
  });

  test('no old archive cannot be mistaken for verified live boundary',
      () async {
    await expectLater(RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: const [],
      brokerPage: const [MarketTick(101, 101)],
      toMs: 101), throwsArgumentError);
  });
}
