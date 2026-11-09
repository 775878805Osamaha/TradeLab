import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/ctrader_candle_stitcher.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  const one = MarketBar(1000, TradeCandle(100, 101, 99, 100.5));
  const two = MarketBar(2000, TradeCandle(100.5, 102, 100, 101));
  const three = MarketBar(3000, TradeCandle(101, 103, 100.7, 102));

  test('append only new source-verified closed cTrader candles', () {
    final existing = [one, two];
    final merged = CTraderCandleStitcher.append(
      existing, [two, three],
    );
    expect(merged.map((bar) => bar.timestamp), [1000, 2000, 3000]);
    expect(merged.last.candle.close, 102);
    expect(existing, hasLength(2));
  });

  test('never invent or fill missing broker market-close minutes', () {
    const later = MarketBar(9000, TradeCandle(102, 104, 101, 103));
    final merged = CTraderCandleStitcher.append(
      [one, two], [two, later],
    );
    expect(merged.map((bar) => bar.timestamp), [1000, 2000, 9000]);
  });

  test('reject mismatched OHLC of an already verified closed candle', () {
    const changed = MarketBar(2000, TradeCandle(100.5, 108, 100, 101));
    expect(() => CTraderCandleStitcher.append(
      [one, two], [changed, three],
    ), throwsA(isA<MarketDataException>()));
  });

  test('reject late broker backfill that would shift Replay indices', () {
    const missing = MarketBar(1500, TradeCandle(100.1, 100.8, 99.5, 100.5));
    expect(() => CTraderCandleStitcher.append(
      [one, two], [missing, two, three],
    ), throwsA(isA<MarketDataException>()));
  });

  test('reject duplicate timestamps in a provider response', () {
    expect(() => CTraderCandleStitcher.append(
      [one], [two, two],
    ), throwsA(isA<MarketDataException>()));
  });
}
