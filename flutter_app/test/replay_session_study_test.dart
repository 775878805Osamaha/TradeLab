import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';
import 'package:tradelab_flutter/replay/replay_cost_estimate.dart';
import 'package:tradelab_flutter/replay/replay_lab_bridge.dart';
import 'package:tradelab_flutter/replay/replay_observed_trade.dart';
import 'package:tradelab_flutter/replay/replay_session_study.dart';

void main() {
  final start = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;
  const flat = TradeCandle(100, 100, 100, 100);
  final bars = <MarketBar>[
    for (var i = 0; i < 40; i++) MarketBar(start + i * 60000, flat),
    MarketBar(start + 40 * 60000,
      const TradeCandle(100, 104, 99.5, 103)),
    MarketBar(start + 41 * 60000,
      const TradeCandle(103, 103, 102, 102.5)),
    MarketBar(start + 42 * 60000,
      const TradeCandle(102.5, 104, 100, 100.5)),
  ];
  ReplayLabSnapshot snapshot(int count, {String account = 'local:guest'}) =>
      ReplayLabSnapshot(accountKey: account, symbol: 'BTCUSDT',
        timeframe: '1m', bars: List.unmodifiable(bars.take(count)));
  ReplayObservedSignal signal(int count, PaperSide side, double stop,
      double target, {ReplayCostEstimate? cost}) =>
      ReplayObservedSignal.fromSnapshot(snapshot: snapshot(count),
        side: side, stopLoss: stop, takeProfit: target,
        costEstimate: cost);
  const study = ReplaySessionStudy();

  test('new signal cannot overlap an open trade or its exit candle', () {
    final first = signal(40, PaperSide.buy, 99, 103);
    final beforeExit = signal(41, PaperSide.buy, 99, 105);
    expect(() => study.validateNext(existing: [first], next: beforeExit,
      snapshot: snapshot(41)), throwsFormatException);
    final stillOpen = signal(40, PaperSide.buy, 98, 110);
    expect(() => study.validateNext(existing: [stillOpen], next: beforeExit,
      snapshot: snapshot(41)), throwsFormatException);
    expect(() => study.validateNext(existing: [first], next: first,
      snapshot: snapshot(40)), throwsFormatException);
  });

  test('sequential historical signals yield realized gross R statistics', () {
    final first = signal(40, PaperSide.buy, 99, 103,
      cost: const ReplayCostEstimate(roundTripPriceUnits: .25));
    final second = signal(42, PaperSide.buy, 101, 105,
      cost: const ReplayCostEstimate(roundTripPriceUnits: .25));
    study.validateNext(existing: const [], next: first,
      snapshot: snapshot(40));
    study.validateNext(existing: [first], next: second,
      snapshot: snapshot(42));
    final report = study.summarize(signals: [first, second],
      snapshot: snapshot(43));
    expect(report.finished, 2);
    expect(report.wins, 1);
    expect(report.winRate, 50);
    expect(report.pending, 0);
    expect(report.open, 0);
    expect(report.unavailable, 0);
    expect(report.totalGrossR, 2); // First +3R, second -1R.
    expect(report.maxDrawdownR, 1);
    expect(report.totalNetR, closeTo(1.5833333333, .0000001));
  });

  test('unknown costs hide net total; rewinding hides future outcomes', () {
    final first = signal(40, PaperSide.buy, 99, 103);
    final second = signal(42, PaperSide.buy, 101, 105,
      cost: const ReplayCostEstimate(roundTripPriceUnits: .25));
    final mixed = study.summarize(signals: [first, second],
      snapshot: snapshot(43));
    expect(mixed.totalNetR, isNull);
    expect(mixed.totalGrossR, 2);

    final rewound = study.summarize(signals: [first, second],
      snapshot: snapshot(40));
    expect(rewound.finished, 0);
    expect(rewound.pending, 1);
    expect(rewound.unavailable, 1);
    expect(rewound.totalGrossR, 0);
  });

  test('rejects other accounts, revised anchors and fabricated signals', () {
    final first = signal(40, PaperSide.buy, 99, 103);
    final next = signal(42, PaperSide.buy, 101, 105);
    expect(() => study.validateNext(existing: [first], next: next,
      snapshot: snapshot(42, account: 'ctrader:other')),
      throwsFormatException);
    expect(() => study.validateNext(existing: const [], next: first,
      snapshot: snapshot(42)), throwsFormatException);
    final revised = [
      ...bars.take(39),
      MarketBar(bars[39].timestamp, const TradeCandle(100, 102, 100, 100)),
      ...bars.skip(40).take(3),
    ];
    final compromised = ReplayLabSnapshot(accountKey: 'local:guest',
      symbol: 'BTCUSDT', timeframe: '1m', bars: List.unmodifiable(revised));
    final report = study.summarize(signals: [first], snapshot: compromised);
    expect(report.finished, 0);
    expect(report.unavailable, 1);
  });
}
