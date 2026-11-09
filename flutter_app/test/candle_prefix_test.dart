import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('Replay exposes a read-only prefix without copying future candles', () {
    final candles = List<TradeCandle>.generate(
      100000, (index) => TradeCandle(index + 1.0, index + 2.0,
          index + .5, index + 1.5),
    );
    final visible = CandlePrefix(candles, 7);
    expect(visible.length, 7);
    expect(identical(visible[6], candles[6]), isTrue);
    expect(() => visible[7], throwsRangeError);
    expect(() => visible[0] = candles[50], throwsUnsupportedError);
    expect(() => visible.length = 20, throwsUnsupportedError);
  });

  test('Replay prefix length is bounded by available market history', () {
    final source = [const TradeCandle(1, 2, .5, 1.5)];
    expect(CandlePrefix(source, 50).length, 1);
    expect(CandlePrefix(source, -1).length, 0);
  });
}
