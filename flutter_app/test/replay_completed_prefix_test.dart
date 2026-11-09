import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/replay/replay_completed_prefix.dart';

void main() {
  test('Binance candles already passed provider close-time validation', () {
    expect(replayCompletedPrefixCount(source: TradeSource.binance,
      availableBars: 80, cursor: 80), 80);
    expect(replayCompletedPrefixCount(source: TradeSource.binance,
      availableBars: 80, cursor: 42), 42);
    expect(replayCompletedPrefixCount(source: TradeSource.binance,
      availableBars: 80, cursor: 900), 80);
  });

  test('cTrader excludes potentially forming bar only at live boundary', () {
    expect(replayCompletedPrefixCount(source: TradeSource.ctrader,
      availableBars: 80, cursor: 80), 79);
    expect(replayCompletedPrefixCount(source: TradeSource.ctrader,
      availableBars: 80, cursor: 42), 42);
    expect(replayCompletedPrefixCount(source: TradeSource.ctrader,
      availableBars: 1, cursor: 1), 0);
  });

  test('empty and invalid cursors never expose future bars', () {
    for (final source in TradeSource.values) {
      expect(replayCompletedPrefixCount(source: source,
        availableBars: 0, cursor: 0), 0);
      expect(replayCompletedPrefixCount(source: source,
        availableBars: 80, cursor: -20), 0);
    }
  });
}
