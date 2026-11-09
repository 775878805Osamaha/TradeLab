import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';
import 'package:tradelab_flutter/replay/replay_cost_estimate.dart';
import 'package:tradelab_flutter/replay/replay_trade_evaluator.dart';

void main() {
  final start = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;
  List<MarketBar> history(List<TradeCandle> candles) => List.generate(
    candles.length, (i) => MarketBar(start + i * 60000, candles[i]));
  const flat = TradeCandle(100, 100, 100, 100);
  const evaluator = ReplayTradeEvaluator();

  test('next-bar open fill is invisible until the next completed bar', () {
    final bars = history([
      ...List.filled(40, flat),
      const TradeCandle(101, 104, 100, 102),
    ]);
    final pending = evaluator.evaluate(sourceBars: bars,
      signalThrough: 40, visibleThrough: 40,
      side: PaperSide.buy, stopLoss: 99, takeProfit: 103);
    expect(pending.status, ReplayTradeStatus.pending);
    expect(pending.entryPrice, isNull); // Future open is still hidden.
    final filled = evaluator.evaluate(sourceBars: bars,
      signalThrough: 40, visibleThrough: 41,
      side: PaperSide.buy, stopLoss: 99, takeProfit: 103);
    expect(filled.entryPrice, 101); // Not the signal bar's close of 100.
    expect(filled.status, ReplayTradeStatus.targeted);
    expect(filled.rMultiple, 1);
  });

  test('an ambiguous bar uses stop first and adverse gaps can exceed -1R', () {
    final ambiguous = history([
      ...List.filled(40, flat),
      const TradeCandle(100, 104, 96, 100),
    ]);
    final outcome = evaluator.evaluate(sourceBars: ambiguous,
      signalThrough: 40, visibleThrough: 41,
      side: PaperSide.buy, stopLoss: 99, takeProfit: 103);
    expect(outcome.status, ReplayTradeStatus.stopped);
    expect(outcome.ambiguousBar, isTrue);
    expect(outcome.rMultiple, -1);

    final gap = history([
      ...List.filled(40, flat),
      const TradeCandle(100, 101, 99.5, 100),
      const TradeCandle(98, 99, 97, 98),
    ]);
    final gapped = evaluator.evaluate(sourceBars: gap,
      signalThrough: 40, visibleThrough: 42,
      side: PaperSide.buy, stopLoss: 99, takeProfit: 103);
    expect(gapped.status, ReplayTradeStatus.stopped);
    expect(gapped.exitPrice, 98);
    expect(gapped.rMultiple, -2);
  });

  test('future movement cannot alter the open trade at an earlier cursor', () {
    final bars = history([
      ...List.filled(40, flat),
      const TradeCandle(100, 101, 99.5, 100.5),
      const TradeCandle(100.5, 150, 50, 120),
    ]);
    final stillOpen = evaluator.evaluate(sourceBars: bars,
      signalThrough: 40, visibleThrough: 41,
      side: PaperSide.buy, stopLoss: 99, takeProfit: 103);
    expect(stillOpen.status, ReplayTradeStatus.open);
    expect(stillOpen.rMultiple, .5);
    final revealed = evaluator.evaluate(sourceBars: bars,
      signalThrough: 40, visibleThrough: 42,
      side: PaperSide.buy, stopLoss: 99, takeProfit: 103);
    expect(revealed.status, ReplayTradeStatus.stopped);
  });

  test('execution cost changes estimated net R, not gross R or fill timing', () {
    final bars = history([
      ...List.filled(40, flat),
      const TradeCandle(100, 101, 99.5, 100.5),
      const TradeCandle(100.5, 104, 100, 103),
    ]);
    const costs = ReplayCostEstimate(roundTripPriceUnits: .5);
    final open = evaluator.evaluate(sourceBars: bars,
      signalThrough: 40, visibleThrough: 41, side: PaperSide.buy,
      stopLoss: 99, takeProfit: 103, costEstimate: costs);
    expect(open.status, ReplayTradeStatus.open);
    expect(open.rMultiple, .5);
    expect(open.netRMultiple, 0); // Gross +0.5R minus 0.5 per unit cost.

    final closed = evaluator.evaluate(sourceBars: bars,
      signalThrough: 40, visibleThrough: 42, side: PaperSide.buy,
      stopLoss: 99, takeProfit: 103, costEstimate: costs);
    expect(closed.status, ReplayTradeStatus.targeted);
    expect(closed.rMultiple, 3);
    expect(closed.netRMultiple, 2.5);
    expect(closed.exitBarIndex, 41);

    final noEstimate = evaluator.evaluate(sourceBars: bars,
      signalThrough: 40, visibleThrough: 41, side: PaperSide.buy,
      stopLoss: 99, takeProfit: 103);
    expect(noEstimate.netRMultiple, isNull,
      reason: 'no cost input must never be presented as zero-cost net');
  });

  test('invalid execution-cost assumptions fail closed', () {
    final bars = history([...List.filled(40, flat)]);
    expect(() => evaluator.evaluate(sourceBars: bars,
      signalThrough: 40, visibleThrough: 40, side: PaperSide.sell,
      stopLoss: 101, takeProfit: 99,
      costEstimate: const ReplayCostEstimate(roundTripPriceUnits: -1)),
      throwsFormatException);
  });

  test('a finished trade never reads later bars in a 100k-candle snapshot', () {
    final bars = _ReadGuardedHistory(
      start: start,
      total: 100100,
      signalThrough: 40,
      firstTradeBar: const TradeCandle(100, 104, 99.5, 103),
    );
    final result = evaluator.evaluate(
      sourceBars: bars,
      signalThrough: 40,
      visibleThrough: bars.length,
      side: PaperSide.buy,
      stopLoss: 99,
      takeProfit: 103,
    );
    expect(result.status, ReplayTradeStatus.targeted);
    expect(result.rMultiple, 3);
    expect(result.exitBarIndex, 40);
    expect(bars.readCount, 1,
      reason: 'closed trades must not scan or copy all revealed future bars');
  });

  test('only evaluated candles must be valid and strictly ordered', () {
    final badBeforeExit = history([
      ...List.filled(40, flat),
      const TradeCandle(100, 101, 99.5, 100),
      const TradeCandle(100, 99, 101, 100), // Invalid OHLC.
    ]);
    expect(() => evaluator.evaluate(sourceBars: badBeforeExit,
      signalThrough: 40, visibleThrough: 42,
      side: PaperSide.buy, stopLoss: 99, takeProfit: 103),
      throwsFormatException);

    final wrongOrder = <MarketBar>[
      ...history(List.filled(40, flat)),
      MarketBar(start + 40 * 60000,
        const TradeCandle(100, 101, 99.5, 100)),
      MarketBar(start + 40 * 60000,
        const TradeCandle(100, 101, 99.5, 100)),
    ];
    expect(() => evaluator.evaluate(sourceBars: wrongOrder,
      signalThrough: 40, visibleThrough: 42,
      side: PaperSide.buy, stopLoss: 99, takeProfit: 103),
      throwsFormatException);

    final badAfterExit = history([
      ...List.filled(40, flat),
      const TradeCandle(100, 104, 99.5, 103),
      const TradeCandle(100, 99, 101, 100), // Not needed after exit.
    ]);
    final finished = evaluator.evaluate(sourceBars: badAfterExit,
      signalThrough: 40, visibleThrough: 42,
      side: PaperSide.buy, stopLoss: 99, takeProfit: 103);
    expect(finished.status, ReplayTradeStatus.targeted);
    expect(finished.exitBarIndex, 40);
  });
}

/// Test sentinel: guarantees a resolved trade never requests any unrelated
/// chart candle, even when the chart advertises a very long visible prefix.
class _ReadGuardedHistory extends ListBase<MarketBar> {
  _ReadGuardedHistory({required this.start, required this.total,
    required this.signalThrough, required this.firstTradeBar});

  final int start;
  final int total;
  final int signalThrough;
  final TradeCandle firstTradeBar;
  int readCount = 0;

  @override
  int get length => total;

  @override
  set length(int value) => throw UnsupportedError('Read-only test history');

  @override
  MarketBar operator [](int index) {
    if (index < 0 || index >= total) throw RangeError.index(index, this);
    if (index != signalThrough) {
      throw StateError('Replay read an unrelated candle at index $index');
    }
    readCount++;
    return MarketBar(start + index * 60000, firstTradeBar);
  }

  @override
  void operator []=(int index, MarketBar value) =>
      throw UnsupportedError('Read-only test history');
}
