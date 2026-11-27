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

  test('stop orders use adverse open when the next bar gaps past stop', () {
    const gap = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(95, 100, 94, 98),
    ];
    final session = ReplayTrainingSession()..moveTo(gap, 1);
    session.enter(side: ReplaySide.buy, candles: gap,
        quantity: 1, stopLoss: 99);
    session.moveTo(gap, 2);
    expect(session.trades.single.exitReason, ReplayExitReason.stopLoss);
    expect(session.trades.single.exitPrice, 95);
    expect(session.realizedPricePnl, -5);
  });

  test('large 120k Replay seek closes 24 practice brackets at first source bar',
      () {
    const count = 120000;
    const safe = TradeCandle(100, 101, 99, 100);
    final candles = List<TradeCandle>.filled(count, safe).toList();
    // A single verified source candle gaps below the long SL AND rises
    // past TP: stop wins; the adverse open 86 is the fill, not stop 90.
    candles[110000] = const TradeCandle(86, 111, 85, 90);
    final session = ReplayTrainingSession()..moveTo(candles, 1);
    expect(ReplayTrainingSession.shouldUseIndexedExitSearch(
        newlyRevealedBars: 110009, watchedTrades: 24), isTrue);
    expect(ReplayTrainingSession.shouldUseIndexedExitSearch(
        newlyRevealedBars: 1, watchedTrades: 24), isFalse);
    expect(ReplayTrainingSession.shouldUseIndexedExitSearch(
        newlyRevealedBars: 110009, watchedTrades: 1), isFalse);
    for (var i = 0; i < 24; i++) {
      session.enter(side: ReplaySide.buy, candles: candles,
          quantity: 1, stopLoss: 90, takeProfit: 110);
    }
    session.moveTo(candles, 110010);
    expect(session.visibleCount, 110010);
    expect(session.openTradeCount, 0);
    expect(session.trades, hasLength(24));
    expect(session.trades.every((trade) =>
        trade.entryIndex == 0 &&
        trade.exitIndex == 110000 &&
        trade.exitPrice == 86 &&
        trade.exitReason == ReplayExitReason.stopLoss), isTrue);
    expect(session.realizedPricePnl, -336); // (86 - 100) * 24

    // Rewinding must erase future executions and discard their source index.
    session.moveTo(candles, 110000);
    expect(session.openTradeCount, 24);
    expect(session.realizedPricePnl, 0);
    session.moveTo(candles, 110001); // one-bar sequential fallback
    expect(session.openTradeCount, 0);
    expect(session.trades.every((trade) =>
        trade.exitIndex == 110000 &&
        trade.exitPrice == 86), isTrue);
    expect(session.realizedPricePnl, -336);
  });

  test('indexed long seek observes entry close, then earliest future candle',
      () {
    const sourceCount = 25000;
    final candles = List<TradeCandle>.filled(
        sourceCount, const TradeCandle(100, 101, 99, 100)).toList();
    // This is the ENTRY candle (index 1000): its high must not trigger
    // a practice short stop entered at its close.
    candles[1000] = const TradeCandle(100, 115, 99, 100);
    candles[8000] = const TradeCandle(100, 104, 94, 98);
    final session = ReplayTrainingSession()..moveTo(candles, 1001);
    for (var i = 0; i < 16; i++) {
      session.enter(side: ReplaySide.sell, candles: candles,
          quantity: 1, stopLoss: 110, takeProfit: 95);
    }
    session.moveTo(candles, 20000);
    expect(session.openTradeCount, 0);
    expect(session.trades.every((t) =>
        t.entryIndex == 1000 && t.entryPrice == 100 &&
        t.exitIndex == 8000 && t.exitPrice == 95 &&
        t.exitReason == ReplayExitReason.takeProfit), isTrue);
    expect(session.realizedPricePnl, 80); // (100 - 95) * 16.
  });

  test('large seek with no practice trades has no side effects', () {
    final candles = List<TradeCandle>.filled(
        100000, const TradeCandle(100, 101, 99, 100));
    final session = ReplayTrainingSession()..moveTo(candles, 80000);
    expect(session.visibleCount, 80000);
    expect(session.trades, isEmpty);
  });

  test('cannot move beyond the available history', () {
    final session = ReplayTrainingSession();
    expect(() => session.moveTo(bars, bars.length + 1), throwsRangeError);
    expect(session.trades, isEmpty);
  });
  test('gap-through long take profit fills at favorable next open', () {
    const gap = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(112, 114, 109, 110),
    ];
    final session = ReplayTrainingSession()..moveTo(gap, 1);
    session.enter(side: ReplaySide.buy, candles: gap,
      quantity: 2, stopLoss: 95, takeProfit: 105);
    session.moveTo(gap, 2);
    expect(session.trades.single.exitReason, ReplayExitReason.takeProfit);
    expect(session.trades.single.exitPrice, 112,
      reason: 'A limit exit crossed between bars fills at the next open');
    expect(session.realizedPricePnl, 24);
  });

  test('gap-through short take profit fills at favorable next open', () {
    const gap = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(88, 91, 85, 90),
    ];
    final session = ReplayTrainingSession()..moveTo(gap, 1);
    session.enter(side: ReplaySide.sell, candles: gap,
      quantity: 3, stopLoss: 105, takeProfit: 95);
    session.moveTo(gap, 2);
    expect(session.trades.single.exitReason, ReplayExitReason.takeProfit);
    expect(session.trades.single.exitPrice, 88);
    expect(session.realizedPricePnl, 36);
  });

  test('already-crossed TP at bar open precedes later intrabar stop', () {
    const longGap = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(112, 114, 88, 90),
    ];
    final longSession = ReplayTrainingSession()..moveTo(longGap, 1);
    longSession.enter(side: ReplaySide.buy, candles: longGap,
      quantity: 1, stopLoss: 95, takeProfit: 105);
    longSession.moveTo(longGap, 2);
    expect(longSession.trades.single.exitPrice, 112);
    expect(longSession.trades.single.exitReason, ReplayExitReason.takeProfit);

    const shortGap = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(88, 108, 85, 106),
    ];
    final shortSession = ReplayTrainingSession()..moveTo(shortGap, 1);
    shortSession.enter(side: ReplaySide.sell, candles: shortGap,
      quantity: 1, stopLoss: 105, takeProfit: 95);
    shortSession.moveTo(shortGap, 2);
    expect(shortSession.trades.single.exitPrice, 88);
    expect(shortSession.trades.single.exitReason, ReplayExitReason.takeProfit);
  });

  test('ordinary intrabar target still fills at exact order level', () {
    const usual = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(101, 108, 100, 106),
    ];
    final s = ReplayTrainingSession()..moveTo(usual, 1);
    s.enter(side: ReplaySide.buy, candles: usual,
      quantity: 1, stopLoss: 95, takeProfit: 105);
    s.moveTo(usual, 2);
    expect(s.trades.single.exitPrice, 105);
  });

  test('indexed deep-seek and one-bar playback agree on TP gap opens', () {
    const count = 12000;
    final candles = List<TradeCandle>.filled(
      count, const TradeCandle(100, 101, 99, 100)).toList();
    candles[10000] = const TradeCandle(112, 113, 88, 90);
    final indexed = ReplayTrainingSession()..moveTo(candles, 1);
    final stepped = ReplayTrainingSession()..moveTo(candles, 1);
    for (var i = 0; i < 12; i++) {
      indexed.enter(side: ReplaySide.buy, candles: candles,
        quantity: 1, stopLoss: 95, takeProfit: 105);
      stepped.enter(side: ReplaySide.buy, candles: candles,
        quantity: 1, stopLoss: 95, takeProfit: 105);
    }
    expect(ReplayTrainingSession.shouldUseIndexedExitSearch(
      newlyRevealedBars: count - 1, watchedTrades: 12), isTrue);
    indexed.moveTo(candles, count);
    for (var i = 2; i <= count; i++) {
      stepped.moveTo(candles, i);
    }
    expect(indexed.realizedPricePnl, 144);
    expect(stepped.realizedPricePnl, 144);
    for (var i = 0; i < 12; i++) {
      expect(indexed.trades[i].exitIndex, 10000);
      expect(indexed.trades[i].exitPrice, 112);
      expect(stepped.trades[i].exitPrice, 112);
    }
  });

  test('buy exits follow TradingView OHLC high-first / low-first path', () {
    const first = TradeCandle(100, 101, 99, 100);
    for (final (next, exit, reason) in <(
        TradeCandle, double, ReplayExitReason)>[
      // OPEN is 6 below HIGH and 20 above LOW -> HIGH first.
      (const TradeCandle(100, 106, 80, 94), 105,
        ReplayExitReason.takeProfit),
      // OPEN is 20 below HIGH and 6 above LOW -> LOW first.
      (const TradeCandle(100, 120, 94, 110), 95,
        ReplayExitReason.stopLoss),
      // OPEN 10 from both extremes; do not invent a price path.
      (const TradeCandle(100, 110, 90, 100), 95,
        ReplayExitReason.stopLoss),
    ]) {
      final bars = [first, next];
      final session = ReplayTrainingSession()..moveTo(bars, 1);
      session.enter(side: ReplaySide.buy, candles: bars,
        quantity: 1, stopLoss: 95, takeProfit: 105);
      session.moveTo(bars, 2);
      expect(session.trades.single.exitPrice, exit);
      expect(session.trades.single.exitReason, reason);
    }
  });

  test('sell exits follow TradingView OHLC high-first / low-first path', () {
    const first = TradeCandle(100, 101, 99, 100);
    for (final (next, exit, reason) in <(
        TradeCandle, double, ReplayExitReason)>[
      // HIGH-first: short stop before short profit.
      (const TradeCandle(100, 106, 80, 94), 105,
        ReplayExitReason.stopLoss),
      // LOW-first: short TP before short stop.
      (const TradeCandle(100, 120, 94, 110), 95,
        ReplayExitReason.takeProfit),
      (const TradeCandle(100, 110, 90, 100), 105,
        ReplayExitReason.stopLoss),
    ]) {
      final bars = [first, next];
      final session = ReplayTrainingSession()..moveTo(bars, 1);
      session.enter(side: ReplaySide.sell, candles: bars,
        quantity: 1, stopLoss: 105, takeProfit: 95);
      session.moveTo(bars, 2);
      expect(session.trades.single.exitPrice, exit);
      expect(session.trades.single.exitReason, reason);
    }
  });

  test('adverse stop gap wins even when intrabar path would favor TP', () {
    const buy = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(90, 110, 89, 106),
    ];
    final a = ReplayTrainingSession()..moveTo(buy, 1);
    a.enter(side: ReplaySide.buy, candles: buy,
      quantity: 1, stopLoss: 95, takeProfit: 105);
    a.moveTo(buy, 2);
    expect(a.trades.single.exitPrice, 90);
    expect(a.trades.single.exitReason, ReplayExitReason.stopLoss);

    const sell = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(110, 111, 89, 94),
    ];
    final b = ReplayTrainingSession()..moveTo(sell, 1);
    b.enter(side: ReplaySide.sell, candles: sell,
      quantity: 1, stopLoss: 105, takeProfit: 95);
    b.moveTo(sell, 2);
    expect(b.trades.single.exitPrice, 110);
    expect(b.trades.single.exitReason, ReplayExitReason.stopLoss);
  });

  test('12k indexed seek has identical intrabar order to one-bar playback',
      () {
    const count = 12000;
    final candles = List<TradeCandle>.filled(
      count, const TradeCandle(100, 101, 99, 100)).toList();
    candles[10000] = const TradeCandle(100, 106, 80, 94);
    final indexed = ReplayTrainingSession()..moveTo(candles, 1);
    final stepped = ReplayTrainingSession()..moveTo(candles, 1);
    for (var n = 0; n < 6; n++) {
      for (final target in [indexed, stepped]) {
        target.enter(side: ReplaySide.buy, candles: candles,
          quantity: 1, stopLoss: 95, takeProfit: 105);
        target.enter(side: ReplaySide.sell, candles: candles,
          quantity: 1, stopLoss: 105, takeProfit: 95);
      }
    }
    expect(ReplayTrainingSession.shouldUseIndexedExitSearch(
      newlyRevealedBars: count - 1, watchedTrades: 12), isTrue);
    indexed.moveTo(candles, count);
    for (var i = 2; i <= count; i++) {
      stepped.moveTo(candles, i);
    }
    for (var i = 0; i < indexed.trades.length; i++) {
      expect(indexed.trades[i].exitIndex, 10000);
      expect(stepped.trades[i].exitIndex, 10000);
      expect(indexed.trades[i].exitPrice, 105,
        reason: 'HIGH-first = buy target, sell stop');
      expect(stepped.trades[i].exitPrice, 105);
      expect(indexed.trades[i].exitReason,
        stepped.trades[i].exitReason);
    }
    expect(indexed.realizedPricePnl, stepped.realizedPricePnl);
  });

}
