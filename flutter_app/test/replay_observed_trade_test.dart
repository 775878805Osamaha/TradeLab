import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';
import 'package:tradelab_flutter/replay/replay_cost_estimate.dart';
import 'package:tradelab_flutter/replay/replay_lab_bridge.dart';
import 'package:tradelab_flutter/replay/replay_observed_trade.dart';
import 'package:tradelab_flutter/replay/replay_trade_evaluator.dart';

void main() {
  const candle = TradeCandle(100, 100, 100, 100);
  final start = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;
  List<MarketBar> history(List<TradeCandle> candles, {int offset = 0}) =>
    List.generate(candles.length, (i) => MarketBar(
      start + (offset + i) * 60000, candles[i]));
  ReplayLabSnapshot snap(List<MarketBar> bars, {String account = 'local:guest',
      String symbol = 'BTCUSDT', String timeframe = '1m'}) =>
      ReplayLabSnapshot(accountKey: account, symbol: symbol,
        timeframe: timeframe, bars: List.unmodifiable(bars));

  test('signal at revealed candle stays pending until next bar is revealed', () {
    final full = history([
      ...List.filled(40, candle),
      const TradeCandle(101, 104, 100, 102),
      const TradeCandle(110, 120, 80, 90),
    ]);
    final signal = ReplayObservedSignal.fromSnapshot(
      snapshot: snap(full.take(40).toList()), side: PaperSide.buy,
      stopLoss: 99, takeProfit: 103);
    const tracker = ReplayObservedTradeTracker();
    final pending = tracker.inspect(signal: signal,
      snapshot: snap(full.take(40).toList()));
    expect(pending.outcome!.status, ReplayTradeStatus.pending);
    expect(pending.outcome!.entryPrice, isNull);

    final visible = tracker.inspect(signal: signal,
      snapshot: snap(full.take(41).toList()));
    expect(visible.outcome!.status, ReplayTradeStatus.targeted);
    expect(visible.outcome!.entryPrice, 101); // Executed after signal.
    expect(visible.outcome!.exitPrice, 103);
    expect(visible.outcome!.rMultiple, 1);
    // The unrevealed 42nd candle must not affect an earlier snapshot.
    expect(tracker.inspect(signal: signal,
      snapshot: snap(full.take(41).toList())).outcome!.rMultiple, 1);
  });

  test('older historical pages can be prepended without shifting the signal', () {
    final original = history([...List.filled(40, candle)]);
    final signal = ReplayObservedSignal.fromSnapshot(
      snapshot: snap(original), side: PaperSide.buy,
      stopLoss: 99, takeProfit: 103);
    final prepended = [
      ...history(List.filled(15, candle), offset: -15),
      ...original,
      MarketBar(start + 40 * 60000,
        const TradeCandle(100, 101, 99.5, 100.5)),
    ];
    final outcome = const ReplayObservedTradeTracker().inspect(
      signal: signal, snapshot: snap(prepended)).outcome!;
    expect(outcome.status, ReplayTradeStatus.open);
    expect(outcome.entryPrice, 100);
    expect(outcome.rMultiple, .5);
    expect(outcome.signalThrough, 55);
  });

  test('changing account, history or symbol invalidates a tracked signal', () {
    final series = history([...List.filled(40, candle)]);
    final signal = ReplayObservedSignal.fromSnapshot(
      snapshot: snap(series), side: PaperSide.buy,
      stopLoss: 99, takeProfit: 103);
    const tracker = ReplayObservedTradeTracker();
    expect(tracker.inspect(signal: signal,
      snapshot: snap(series, account: 'ctrader:99')).available, isFalse);
    expect(tracker.inspect(signal: signal,
      snapshot: snap(series, symbol: 'XAUUSD')).available, isFalse);
    expect(tracker.inspect(signal: signal,
      snapshot: snap(series, timeframe: '15m')).available, isFalse);
    expect(tracker.inspect(signal: signal,
      snapshot: snap(series.take(39).toList())).available, isFalse);
    final revised = [
      ...series.take(39),
      MarketBar(series.last.timestamp,
        const TradeCandle(101, 101, 101, 101)),
    ];
    expect(tracker.inspect(signal: signal,
      snapshot: snap(revised)).available, isFalse);
    final highRevisedOnly = [
      ...series.take(39),
      MarketBar(series.last.timestamp,
        const TradeCandle(100, 102, 100, 100)),
    ];
    expect(tracker.inspect(signal: signal,
      snapshot: snap(highRevisedOnly)).available, isFalse,
      reason: 'changed high/low must invalidate a signal even if close matches');
  });

  test('invalid stop or next-open gap never creates a fictional fill', () {
    final bars = history([...List.filled(40, candle)]);
    expect(() => ReplayObservedSignal.fromSnapshot(
      snapshot: snap(bars), side: PaperSide.buy,
      stopLoss: 101, takeProfit: 103), throwsFormatException);
    final signal = ReplayObservedSignal.fromSnapshot(
      snapshot: snap(bars), side: PaperSide.buy,
      stopLoss: 99, takeProfit: 103);
    final gap = [...bars,
      MarketBar(start + 40 * 60000,
        const TradeCandle(105, 106, 104, 105))];
    final outcome = const ReplayObservedTradeTracker().inspect(
      signal: signal, snapshot: snap(gap));
    expect(outcome.available, isFalse);
    expect(outcome.reason, contains('فجوة'));
  });

  test('observed signal preserves entered cost as the Replay cursor advances', () {
    final source = history([...List.filled(40, candle),
      const TradeCandle(100, 101, 99.5, 100.5)]);
    final signal = ReplayObservedSignal.fromSnapshot(
      snapshot: snap(source.take(40).toList()), side: PaperSide.buy,
      stopLoss: 99, takeProfit: 103,
      costEstimate: const ReplayCostEstimate(roundTripPriceUnits: .25));
    const tracker = ReplayObservedTradeTracker();
    final pending = tracker.inspect(signal: signal,
      snapshot: snap(source.take(40).toList())).outcome!;
    expect(pending.netRMultiple, isNull);
    final observed = tracker.inspect(signal: signal,
      snapshot: snap(source)).outcome!;
    expect(observed.rMultiple, .5);
    expect(observed.netRMultiple, .25);
  });

  test('malformed revealed market bars fail closed with a visible reason', () {
    final seed = history([...List.filled(40, candle)]);
    final signal = ReplayObservedSignal.fromSnapshot(
      snapshot: snap(seed), side: PaperSide.buy,
      stopLoss: 99, takeProfit: 103);
    final damaged = [
      ...seed,
      MarketBar(start + 40 * 60000,
        const TradeCandle(100, 102, 99.5, 100.5)),
      MarketBar(start + 41 * 60000,
        const TradeCandle(100.5, 100, 101, 100.5)),
    ];
    final report = const ReplayObservedTradeTracker().inspect(
      signal: signal, snapshot: snap(damaged));
    expect(report.available, isFalse);
    expect(report.reason, contains('OHLC'));
  });
}
