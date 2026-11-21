import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_verified_bid_window_slice.dart';

class _MeasuredVerifiedTicks extends ListBase<MarketTick> {
  _MeasuredVerifiedTicks(this.source);

  final List<MarketTick> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Verified broker cache must remain read-only');

  @override
  MarketTick operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, MarketTick value) =>
      throw UnsupportedError('Verified broker cache must remain read-only');
}

void main() {
  test('120k cached BID events: short request reads logarithmic source indexes',
      () {
    const start = 1700000000000;
    final source = List<MarketTick>.generate(120000, (i) =>
        MarketTick(start + i ~/ 2, 3900.0 + i * .0001), growable: false);
    final measured = _MeasuredVerifiedTicks(source);
    final result = <MarketTick>[MarketTick(start - 1, 3899.9)];
    final ok = RangeVerifiedBidWindowSlice.appendWithinLimit(
      verified: measured,
      fromMs: start + 59990,
      toMs: start + 59993,
      output: result,
      maxTicks: 20,
    );
    expect(ok, isTrue);
    expect(result.length, 9);
    expect(result.first.timestamp, start - 1);
    expect(result.skip(1).map((t) => t.timestamp), [
      start + 59990, start + 59990,
      start + 59991, start + 59991,
      start + 59992, start + 59992,
      start + 59993, start + 59993,
    ]);
    expect(result[1].bid, source[119980].bid);
    expect(result.last.bid, source[119987].bid);
    expect(measured.reads, lessThanOrEqualTo(50),
      reason: 'Only O(log 120k) source reads plus eight returned ticks');
    expect(source, hasLength(120000));
  });

  test('inclusive identical-millisecond BID events preserve every ordinal',
      () {
    final source = <MarketTick>[
      MarketTick(100, 2000), MarketTick(101, 2001),
      MarketTick(101, 2001.1), MarketTick(101, 2001.2),
      MarketTick(102, 2002), MarketTick(104, 2004),
    ];
    final data = <MarketTick>[];
    expect(RangeVerifiedBidWindowSlice.appendWithinLimit(
      verified: source, fromMs: 101, toMs: 101,
      output: data, maxTicks: 5,
    ), isTrue);
    expect(data.map((t) => t.bid), [2001, 2001.1, 2001.2]);
    expect(identical(data[0], source[1]), isTrue,
      reason: 'No synthetic replacement/sort/round of real BID ticks');
  });

  test('empty and quiet slices do not fabricate cached history', () {
    final source = <MarketTick>[
      MarketTick(100, 2000), MarketTick(110, 2010),
    ];
    final output = <MarketTick>[];
    for (final interval in <(int, int)>[(101, 109), (111, 119), (1, 99)]) {
      expect(RangeVerifiedBidWindowSlice.appendWithinLimit(
        verified: source,
        fromMs: interval.$1, toMs: interval.$2,
        output: output, maxTicks: 10,
      ), isTrue);
      expect(output, isEmpty);
    }
    expect(RangeVerifiedBidWindowSlice.appendWithinLimit(
      verified: const <MarketTick>[],
      fromMs: 100, toMs: 100,
      output: output, maxTicks: 10,
    ), isTrue);
    expect(output, isEmpty);
  });

  test('memory limit rejects entire slice before any output mutation', () {
    final ticks = List<MarketTick>.generate(1000,
      (i) => MarketTick(100 + i ~/ 2, 3900.0 + i * .01));
    final existing = <MarketTick>[MarketTick(10, 100)];
    expect(RangeVerifiedBidWindowSlice.appendWithinLimit(
      verified: ticks, fromMs: 100, toMs: 101,
      output: existing, maxTicks: 4,
    ), isFalse);
    expect(existing, hasLength(1));
    expect(existing.single.bid, 100);
    expect(RangeVerifiedBidWindowSlice.appendWithinLimit(
      verified: ticks, fromMs: 100, toMs: 101,
      output: existing, maxTicks: 5,
    ), isTrue);
    expect(existing.map((tick) => tick.bid),
        [100, 3900, 3900.01, 3900.02, 3900.03]);
  });

  test('adjacent cached verified windows cannot repeat boundary tick events',
      () {
    final output = <MarketTick>[];
    final a = <MarketTick>[
      MarketTick(100, 2000), MarketTick(101, 2001),
      MarketTick(101, 2001.1),
    ];
    final b = <MarketTick>[
      MarketTick(102, 2002), MarketTick(102, 2002.1),
      MarketTick(103, 2003),
    ];
    expect(RangeVerifiedBidWindowSlice.appendWithinLimit(
      verified: a, fromMs: 100, toMs: 101,
      output: output, maxTicks: 10,
    ), isTrue);
    expect(RangeVerifiedBidWindowSlice.appendWithinLimit(
      verified: b, fromMs: 102, toMs: 103,
      output: output, maxTicks: 10,
    ), isTrue);
    expect(output.map((t) => t.bid),
        [2000, 2001, 2001.1, 2002, 2002.1, 2003]);
  });

  test('invalid slice constraints fail without touching caller output', () {
    final output = <MarketTick>[MarketTick(100, 2000)];
    for (final bounds in <(int, int, int)>[
      (-1, 100, 2), (200, 100, 2), (0, 100, 0), (0, 100, 0),
    ]) {
      expect(() => RangeVerifiedBidWindowSlice.appendWithinLimit(
        verified: const <MarketTick>[],
        fromMs: bounds.$1, toMs: bounds.$2,
        output: output, maxTicks: bounds.$3,
      ), throwsArgumentError);
    }
    expect(output, hasLength(1));
  });
}
