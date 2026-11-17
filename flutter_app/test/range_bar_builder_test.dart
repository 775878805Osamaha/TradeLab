import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/range_bar_builder.dart';

void main() {
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

}
