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

  test('previews respond to different range configurations', () {
    final small = previewRangeCandles(100);
    final large = previewRangeCandles(1000);
    expect(small.length, greaterThan(large.length));
    expect(previewRangeCandles(100), hasLength(small.length));
  });
}
