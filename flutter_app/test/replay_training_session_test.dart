import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/replay/replay_training_session.dart';

void main() {
  const bars = [
    TradeCandle(100, 103, 99, 101),
    TradeCandle(101, 108, 100, 106),
    TradeCandle(106, 107, 90, 96),
    TradeCandle(96, 106, 94, 102),
  ];

  test('entry uses only last revealed close, not later candles', () {
    final session = ReplayTrainingSession()..moveTo(bars, 1);
    final trade = session.enter(
      side: ReplaySide.buy, candles: bars, quantity: 2,
      stopLoss: 99, takeProfit: 105,
    );
    expect(trade.entryPrice, 101);
    expect(trade.entryIndex, 0);
    expect(trade.isOpen, isTrue);
    // The entry candle's range is never used to trigger stops or targets.
    expect(session.openTradeCount, 1);
    session.moveTo(bars, 2);
    expect(session.trades.single.exitIndex, 1);
    expect(session.trades.single.exitReason, ReplayExitReason.takeProfit);
    expect(session.realizedPricePnl, 8); // (105 - 101) * 2.
  });

  test('SL takes precedence when same revealed candle hits SL and TP', () {
    final session = ReplayTrainingSession()..moveTo(bars, 1);
    session.enter(side: ReplaySide.buy, candles: bars,
      quantity: 1, stopLoss: 100, takeProfit: 105);
    session.moveTo(bars, 2);
    expect(session.trades.single.exitPrice, 100);
    expect(session.trades.single.exitReason, ReplayExitReason.stopLoss);
    expect(session.realizedPricePnl, -1);
  });

  test('short stop and target direction is validated', () {
    final session = ReplayTrainingSession()..moveTo(bars, 2);
    expect(() => session.enter(side: ReplaySide.sell, candles: bars,
      quantity: 1, stopLoss: 105), throwsArgumentError);
    session.enter(side: ReplaySide.sell, candles: bars,
        quantity: 1, stopLoss: 110, takeProfit: 100);
    session.moveTo(bars, 3);
    expect(session.trades.single.exitReason, ReplayExitReason.takeProfit);
    expect(session.realizedPricePnl, 6);
  });

  test('rewinding erases future entries and undoes future exits', () {
    final session = ReplayTrainingSession()..moveTo(bars, 1);
    session.enter(side: ReplaySide.buy, candles: bars,
        quantity: 1, takeProfit: 105);
    session.moveTo(bars, 2);
    expect(session.trades.single.isOpen, isFalse);
    session.enter(side: ReplaySide.sell, candles: bars, quantity: 1);
    session.moveTo(bars, 1);
    expect(session.trades, hasLength(1));
    expect(session.trades.single.isOpen, isTrue);
    expect(session.realizedPricePnl, 0);
    session.moveTo(bars, 2);
    expect(session.trades.single.exitIndex, 1);
  });

  test('old history prepend preserves trade/cutoff anchor', () {
    final session = ReplayTrainingSession()..moveTo(bars, 2);
    session.enter(side: ReplaySide.buy, candles: bars, quantity: 1);
    session.prepend(3);
    expect(session.visibleCount, 5);
    expect(session.trades.single.entryIndex, 4);
  });

  test('manual close and guards require known price and size', () {
    final session = ReplayTrainingSession();
    expect(() => session.enter(side: ReplaySide.buy,
        candles: bars, quantity: 1), throwsStateError);
    session.moveTo(bars, 2);
    expect(() => session.enter(side: ReplaySide.buy,
        candles: bars, quantity: 0), throwsArgumentError);
    final trade = session.enter(
        side: ReplaySide.sell, candles: bars, quantity: 3);
    session.moveTo(bars, 3);
    session.closeAtCurrent(trade.id, bars);
    expect(session.trades.single.exitReason, ReplayExitReason.manual);
    expect(session.realizedPricePnl, 30); // (106 - 96) * 3.
    expect(() => session.closeAtCurrent(trade.id, bars), throwsStateError);
  });

  test('cannot move beyond the available history', () {
    final session = ReplayTrainingSession();
    expect(() => session.moveTo(bars, bars.length + 1), throwsRangeError);
    expect(session.trades, isEmpty);
  });
}
