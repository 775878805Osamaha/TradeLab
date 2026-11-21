import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/replay/replay_training_session.dart';

/// Counts market candle reads. A closed or unprotected trade must never
/// trigger 100,000 redundant history accesses during a Replay seek.
class _CountingCandles extends ListBase<TradeCandle> {
  _CountingCandles(this.source);
  final List<TradeCandle> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) => throw UnsupportedError('read-only source');

  @override
  TradeCandle operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('read-only source');
}

void main() {
  const flat = TradeCandle(100, 101, 99, 100);

  test('100k-bar seek with unprotected open trade reads no skipped candles', () {
    final candles = _CountingCandles(
        List<TradeCandle>.filled(100000, flat));
    final session = ReplayTrainingSession()..moveTo(candles, 1);
    final entry = session.enter(
        side: ReplaySide.buy, candles: candles, quantity: 1);
    candles.reads = 0;
    session.moveTo(candles, 100000);
    expect(candles.reads, 0);
    expect(session.visibleCount, 100000);
    expect(session.trades.single.isOpen, isTrue);
    session.closeAtCurrent(entry.id, candles);
    expect(candles.reads, 1);
    expect(session.trades.single.exitIndex, 99999);
  });

  test('100k-bar seek after stop settlement reads no subsequent candles', () {
    final raw = List<TradeCandle>.filled(100000, flat);
    raw[1] = const TradeCandle(95, 101, 94, 98);
    final candles = _CountingCandles(raw);
    final session = ReplayTrainingSession()..moveTo(candles, 1);
    session.enter(
        side: ReplaySide.buy, candles: candles,
        quantity: 2, stopLoss: 99);
    session.moveTo(candles, 2);
    expect(session.trades.single.exitReason, ReplayExitReason.stopLoss);
    expect(session.trades.single.exitPrice, 95);
    candles.reads = 0;
    session.moveTo(candles, 100000);
    expect(candles.reads, 0);
    expect(session.realizedPricePnl, -10);
  });

  test('independent open exits keep SL priority and unprotected trades open',
      () {
    const bars = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(95, 110, 94, 103),
      TradeCandle(103, 104, 102, 103),
    ];
    final session = ReplayTrainingSession()..moveTo(bars, 1);
    session.enter(side: ReplaySide.buy, candles: bars, quantity: 1,
        stopLoss: 99, takeProfit: 105);
    session.enter(side: ReplaySide.sell, candles: bars, quantity: 1,
        stopLoss: 105, takeProfit: 95);
    session.enter(side: ReplaySide.buy, candles: bars, quantity: 1);
    session.moveTo(bars, 3);
    expect(session.trades[0].exitPrice, 95);
    expect(session.trades[0].exitReason, ReplayExitReason.stopLoss);
    expect(session.trades[1].exitPrice, 105);
    expect(session.trades[1].exitReason, ReplayExitReason.stopLoss);
    expect(session.trades[2].isOpen, isTrue);
    expect(session.realizedPricePnl, -10);
  });

  test('rewind and re-advance reprocesses only revealed future exits', () {
    const bars = [
      TradeCandle(100, 101, 99, 100),
      TradeCandle(100, 110, 99, 108),
      TradeCandle(108, 109, 107, 108),
    ];
    final session = ReplayTrainingSession()..moveTo(bars, 1);
    session.enter(side: ReplaySide.buy, candles: bars, quantity: 1,
        takeProfit: 105);
    session.moveTo(bars, 3);
    expect(session.trades.single.exitIndex, 1);
    session.moveTo(bars, 1);
    expect(session.trades.single.isOpen, isTrue);
    session.moveTo(bars, 3);
    expect(session.trades.single.exitIndex, 1);
    expect(session.trades.single.exitPrice, 105);
  });
}
