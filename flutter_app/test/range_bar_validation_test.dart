import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/range_bar_builder.dart';

void main() {
  group('RangeBarBuilder input validation', () {
    test('rejects invalid range distances in all build modes', () {
      for (final distance in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => RangeBarBuilder(distance), throwsArgumentError);
      }
    });

    test('rejects invalid BID ticks without creating bars', () {
      final builder = RangeBarBuilder(1);
      for (final bid in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => builder.appendBidTick(bid), throwsArgumentError);
      }
      expect(builder.snapshot(), isEmpty);
    });

    test('a large BID jump closes multiple deterministic bars', () {
      final builder = RangeBarBuilder(1);
      builder.appendBidTick(100);
      builder.appendBidTick(103.5);
      expect(builder.closed.length, 3);
      expect(builder.closed.map((bar) => bar.close).toList(),
          [101.0, 102.0, 103.0]);
      expect(builder.forming!.close, 103.5);
    });
  });
}
