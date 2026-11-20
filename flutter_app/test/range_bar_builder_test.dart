import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/range_bar_builder.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('verified forming Range state resumes exactly without old tick replay',
      () {
    const prices = <double>[100, 100.7, 102.4, 101.2];
    final old = RangeBarBuilder(1);
    for (final price in prices) old.appendBidTick(price);
    final frozen = old.sealSnapshot();
    final resumed = RangeBarBuilder.resumeFromVerifiedForming(
        1, frozen.last);
    final uninterrupted = RangeBarBuilder(1);
    for (final price in prices) uninterrupted.appendBidTick(price);
    const incoming = <double>[101.6, 102.8, 100.3, 99.8];
    for (final price in incoming) {
      resumed.appendBidTick(price);
      uninterrupted.appendBidTick(price);
    }
    final resumedBars = resumed.sealSnapshot();
    final full = uninterrupted.sealSnapshot();
    expect([
      ...frozen.take(frozen.length - 1), ...resumedBars,
    ].map((bar) => (bar.open, bar.high, bar.low, bar.close)),
    full.map((bar) => (bar.open, bar.high, bar.low, bar.close)));
    expect(() => RangeBarBuilder.resumeFromVerifiedForming(
        1, const TradeCandle(100, 90, 101, 100)),
        throwsArgumentError);
    expect(() => RangeBarBuilder.resumeFromVerifiedForming(
        0, frozen.last), throwsArgumentError);
  });

  test('starts with a forming bar and no artificial completion', () {
    final bars = RangeBarBuilder(1);
    bars.appendBidTick(100);
    bars.appendBidTick(100.7);
    expect(bars.closed, isEmpty);
    expect(bars.forming!.close, 100.7);
  });

  test('closes at boundary and handles multiple bars from a gap', () {
    final bars = RangeBarBuilder(1);
    bars.appendBidTick(100);
    bars.appendBidTick(102.3);
    expect(bars.closed.length, 2);
    expect(bars.closed[0].close, 101);
    expect(bars.closed[1].close, 102);
    expect(bars.forming!.close, 102.3);
    bars.appendBidTick(100.9);
    expect(bars.closed.last.close, 101);
  });

  test('future ticks cannot modify already closed bars', () {
    final bars = RangeBarBuilder(.5);
    bars.appendBidTick(50);
    bars.appendBidTick(50.7);
    final first = bars.closed.first;
    bars.appendBidTick(46);
    expect(first.open, 50);
    expect(first.close, 50.5);
    expect(bars.closed.first.close, first.close);
  });

  test('the same supplied BID ticks produce different range sizes', () {
    const ticks = [100.0, 100.4, 100.8, 101.3, 101.9, 102.5];
    final small = RangeBarBuilder(.5);
    final large = RangeBarBuilder(2);
    for (final tick in ticks) {
      small.appendBidTick(tick);
      large.appendBidTick(tick);
    }
    expect(small.closed.length, greaterThan(large.closed.length));
    expect(small.closed.first.close, 100.5);
  });
  test('sub-ULP Range distance cannot lock the BID candle builder', () {
    final bars = RangeBarBuilder(1e-16);
    bars.appendBidTick(100.0);
    expect(() => bars.appendBidTick(100.00000000000001),
        throwsStateError);
    expect(bars.closed, isEmpty);
    expect(bars.forming!.close, 100);
  });

  test('extreme single tick expansion fails before changing confirmed bars', () {
    final bars = RangeBarBuilder(1);
    bars.appendBidTick(100);
    bars.appendBidTick(102);
    expect(bars.closed.length, 2);
    expect(() => bars.appendBidTick(
        102.0 + RangeBarBuilder.maxBarsPerSingleTick + 10),
        throwsStateError);
    expect(bars.closed.length, 2);
    expect(bars.closed.last.close, 102);
    expect(bars.forming!.close, 102);
  });

  test('normal multi-candle broker gaps stay deterministic', () {
    final bars = RangeBarBuilder(.5);
    bars.appendBidTick(100);
    bars.appendBidTick(102);
    expect(bars.closed.map((bar) => bar.close), [100.5, 101, 101.5, 102]);
    expect(bars.forming!.open, 102);
    expect(bars.forming!.close, 102);
  });


  test('sealing a verified Range buffer preserves completed and forming bars',
      () {
    final builder = RangeBarBuilder(1);
    for (final price in <double>[100, 100.7, 102.4, 101.2, 99.8]) {
      builder.appendBidTick(price);
    }
    final before = builder.snapshot();
    final beforeClosed = builder.closed;
    final count = builder.closedCount;
    expect(count, greaterThan(0));
    final sealed = builder.sealSnapshot();
    expect(sealed, hasLength(before.length));
    for (var i = 0; i < sealed.length; i++) {
      expect((sealed[i].open, sealed[i].high, sealed[i].low,
          sealed[i].close),
          (before[i].open, before[i].high, before[i].low, before[i].close));
    }
    expect(builder.closedCount, count,
        reason: 'The final forming bar is not an executed Range close');
    expect(builder.closed, hasLength(count));
    expect(builder.snapshot(), hasLength(before.length));
    expect(builder.snapshot(includeForming: false), hasLength(count));
    expect(beforeClosed, hasLength(count));
    expect(() => builder.appendBidTick(104), throwsStateError,
        reason: 'Worker must not mutate the published timeline');
    expect(() => builder.sealSnapshot(), throwsStateError,
        reason: 'The owned array can only be transferred once');
    expect(sealed, hasLength(before.length));
    expect(before, hasLength(before.length));
  });

  test('sealing without forming bar preserves completed-only history', () {
    final builder = RangeBarBuilder(.5);
    builder.appendBidTick(50);
    builder.appendBidTick(51.2);
    final closedCount = builder.closedCount;
    final sealed = builder.sealSnapshot(includeForming: false);
    expect(sealed, hasLength(closedCount));
    expect(builder.closedCount, closedCount);
    expect(builder.closed, hasLength(closedCount));
    expect(builder.snapshot(includeForming: false), hasLength(closedCount));
    expect(builder.snapshot(), hasLength(closedCount + 1));
    expect(() => builder.appendBidTick(52), throwsStateError);
  });

  test('empty source transfers an empty Range buffer, not a phantom bar', () {
    final builder = RangeBarBuilder(1);
    final sealed = builder.sealSnapshot();
    expect(sealed, isEmpty);
    expect(builder.forming, isNull);
    expect(builder.closedCount, 0);
    expect(builder.snapshot(), isEmpty);
    expect(() => builder.appendBidTick(100), throwsStateError);
  });
}
