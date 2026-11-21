import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_live_bid_delta.dart';
import 'package:tradelab_flutter/data/range_bar_timeline.dart';



class _OversizedBidHistory extends ListBase<MarketTick> {
  @override
  int get length => RangeLiveBidBoundary.maxVerifiedSourceTicks + 1;

  @override
  set length(int value) => throw UnsupportedError('Immutable source');

  @override
  MarketTick operator [](int index) =>
      throw StateError('Oversized source must fail before any tick read');

  @override
  void operator []=(int index, MarketTick value) =>
      throw UnsupportedError('Immutable source');
}

class _MillionBidHistory extends ListBase<MarketTick> {
  static const total = 1000000;
  static const boundaryCount = 5;
  static const boundaryMs = total - boundaryCount;

  int reads = 0;

  @override
  int get length => total;

  @override
  set length(int value) =>
      throw UnsupportedError('Source verified history is immutable');

  @override
  MarketTick operator [](int index) {
    if (index < 0 || index >= length) throw RangeError.index(index, this);
    reads++;
    return MarketTick(
        index < boundaryMs ? index : boundaryMs,
        100.0 + (index % 13));
  }

  @override
  void operator []=(int index, MarketTick value) =>
      throw UnsupportedError('Source verified history is immutable');
}

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


  test('boundary guard rejects oversized historical archive before tick access',
      () {
    expect(() => RangeLiveBidBoundary.fromVerified(
        _OversizedBidHistory()), throwsA(isA<MarketDataException>()));
  });

  test('1m verified BID archive contributes ONLY last-ms events to the worker',
      () async {
    final source = _MillionBidHistory();
    final boundary = RangeLiveBidBoundary.fromVerified(source);
    expect(boundary.timestampMs, _MillionBidHistory.boundaryMs);
    expect(boundary.events.length, _MillionBidHistory.boundaryCount);
    expect(boundary.events.map((tick) => tick.bid), [
      for (var i = _MillionBidHistory.boundaryMs;
          i < _MillionBidHistory.total; i++)
        100.0 + (i % 13),
    ]);
    expect(source.reads, lessThan(50),
        reason: 'No full archived history scan or copy on chart UI isolate');
    expect(() => boundary.events.add(const MarketTick(100, 100)),
        throwsUnsupportedError);
    final page = <MarketTick>[
      ...boundary.events,
      for (var i = 0; i < 6500; i++)
        MarketTick(_MillionBidHistory.boundaryMs + 1 + i,
            200.0 + (i % 17)),
    ];
    source.reads = 0;
    final suffix = await RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: source,
      brokerPage: page,
      toMs: _MillionBidHistory.boundaryMs + 6501,
    );
    expect(suffix.length, 6500);
    expect(suffix.first.timestamp, _MillionBidHistory.boundaryMs + 1);
    expect(suffix.last.timestamp, _MillionBidHistory.boundaryMs + 6500);
    expect(source.reads, lessThan(50),
        reason: 'A 6500-tick isolate poll must transfer only the final '
                '5 same-ms events, never the 1m-tick historical list');
  });

  test('same-ms duplicate multiplicity and invalid boundary fail closed',
      () async {
    const original = <MarketTick>[
      MarketTick(80, 100), MarketTick(81, 101),
      MarketTick(81, 101), MarketTick(81, 101),
    ];
    final boundary = RangeLiveBidBoundary.fromVerified(original);
    expect(boundary.events.map((e) => e.bid), [101, 101, 101]);
    final fine = await RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: original,
      brokerPage: const [
        MarketTick(81, 101), MarketTick(81, 101), MarketTick(81, 101),
        MarketTick(81, 101), MarketTick(82, 102),
      ],
      toMs: 82);
    expect(fine.map((t) => t.timestamp), [81, 82]);
    await expectLater(RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: original,
      brokerPage: const [
        MarketTick(81, 101), MarketTick(81, 101),
        MarketTick(82, 102),
      ],
      toMs: 82), throwsA(isA<MarketDataException>()));
    expect(() => RangeLiveBidBoundary.fromVerified(
      const <MarketTick>[MarketTick(12, -1)]),
      throwsA(isA<MarketDataException>()));
    expect(() => RangeLiveBidBoundary.fromVerified(
      const <MarketTick>[]), throwsArgumentError);
  });

  test('single-pass live verifier preserves 4999/5000 event worker parity',
      () async {
    const source = <MarketTick>[
      MarketTick(100, 100), MarketTick(101, 101),
    ];
    List<MarketTick> page(int count) => <MarketTick>[
      const MarketTick(101, 101),
      for (var i = 0; i < count - 1; i++)
        MarketTick(102 + i, 100.0 + i * .01),
    ];
    for (final count in [4999, 5000, 6501]) {
      final response = page(count);
      final suffix = await RangeLiveBidDelta.verifiedSuffixAsync(
        previouslyVerified: source,
        brokerPage: response,
        toMs: 10000,
      );
      expect(suffix.length, count - 1);
      expect(suffix.first.timestamp, 102);
      expect(suffix.last.timestamp, 100 + count);
      expect(suffix.first.bid, 100);
      expect(() => suffix.add(const MarketTick(0, 100)),
          throwsUnsupportedError);
    }
    expect(source, hasLength(2));
  });

  test('large BID page validates full order, timestamps and prices in worker',
      () async {
    const source = <MarketTick>[
      MarketTick(100, 100),
      MarketTick(101, 101),
      MarketTick(101, 101),
    ];
    List<MarketTick> valid() => <MarketTick>[
      const MarketTick(101, 101),
      const MarketTick(101, 101),
      for (var i = 0; i < 5000; i++)
        MarketTick(102 + i, 100.0 + i * .01),
    ];
    final reversed = valid()..[4500] = const MarketTick(101, 102);
    final outsideRange = valid()
      ..[5001] = const MarketTick(9000, 102);
    final invalidBid = valid()..[4999] = const MarketTick(4999, -1);
    final revisedOverlap = valid()
      ..[1] = const MarketTick(101, 100.99);
    for (final page in [reversed, outsideRange, invalidBid, revisedOverlap]) {
      await expectLater(RangeLiveBidDelta.verifiedSuffixAsync(
        previouslyVerified: source, brokerPage: page, toMs: 7000),
        throwsA(isA<MarketDataException>()),
        reason: 'A worker may not return a suffix from a broken source page');
    }
    // All same-ms events remain genuine, including exact-price repeats.
    final verified = await RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: source,
      brokerPage: valid(), toMs: 7000);
    expect(verified, hasLength(5000));
    expect(verified.first.timestamp, 102);
    expect(verified.last.timestamp, 5101);
  });

  test('no old archive cannot be mistaken for verified live boundary',
      () async {
    await expectLater(RangeLiveBidDelta.verifiedSuffixAsync(
      previouslyVerified: const [],
      brokerPage: const [MarketTick(101, 101)],
      toMs: 101), throwsArgumentError);
  });
}
