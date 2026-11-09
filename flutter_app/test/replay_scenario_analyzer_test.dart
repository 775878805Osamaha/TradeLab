import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';
import 'package:tradelab_flutter/replay/replay_cost_estimate.dart';
import 'package:tradelab_flutter/replay/replay_scenario_analyzer.dart';

void main() {
  final start = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;
  List<MarketBar> bars(int count, {double high = 100, double low = 100}) =>
      List.generate(count, (index) => MarketBar(start + index * 60000,
        TradeCandle(100, high, low, 100)));
  const analyzer = ReplayScenarioAnalyzer();

  test('Monte Carlo is deterministic and sums to its sample count', () {
    final history = bars(40, high: 101, low: 99);
    ReplayScenarioResult run() => analyzer.simulate(
      sourceBars: history, visibleThrough: 40, side: PaperSide.buy,
      stopLoss: 99.5, takeProfit: 100.5, samples: 1000, seed: 19);
    final first = run();
    final second = run();
    expect(first.targetFirst + first.stopFirst + first.neither, 1000);
    expect(first.meanR, second.meanR);
    expect(first.stopFirst, 1000); // ambiguous high/low -> conservative stop.
    expect(first.targetFirst, 0);
  });

  test('future bars are never sampled beyond the Replay cursor', () {
    final prefix = bars(40);
    final baseline = analyzer.simulate(sourceBars: prefix, visibleThrough: 40,
      side: PaperSide.buy, stopLoss: 95, takeProfit: 105,
      horizonBars: 10, seed: 7);
    final future = List<MarketBar>.of(prefix)..addAll(
      List.generate(10, (i) => MarketBar(start + (40 + i) * 60000,
        const TradeCandle(100, 180, 20, 120))));
    final hidden = analyzer.simulate(sourceBars: future, visibleThrough: 40,
      side: PaperSide.buy, stopLoss: 95, takeProfit: 105,
      horizonBars: 10, seed: 7);
    expect(hidden.targetFirst, baseline.targetFirst);
    expect(hidden.stopFirst, baseline.stopFirst);
    expect(hidden.meanR, baseline.meanR);
    expect(hidden.visibleBars, 40);
    expect(hidden.neither, baseline.neither);
  });

  test('short directions, invalid risk plans, and insufficient history', () {
    final history = bars(40, high: 100.1, low: 99.9);
    final short = analyzer.simulate(sourceBars: history, visibleThrough: 40,
      side: PaperSide.sell, stopLoss: 102, takeProfit: 98,
      horizonBars: 5, seed: 2);
    expect(short.neither, 1000);
    expect(short.meanR, closeTo(0, 0.000001));
    expect(() => analyzer.simulate(sourceBars: history, visibleThrough: 29,
      side: PaperSide.buy, stopLoss: 98, takeProfit: 102),
      throwsFormatException);
    expect(() => analyzer.simulate(sourceBars: history, visibleThrough: 41,
      side: PaperSide.buy, stopLoss: 98, takeProfit: 102),
      throwsFormatException);
    expect(() => analyzer.simulate(sourceBars: history, visibleThrough: 40,
      side: PaperSide.buy, stopLoss: 102, takeProfit: 98),
      throwsFormatException);
  });

  test('net scenario distribution subtracts only the stated round-trip cost', () {
    final source = bars(40, high: 100.1, low: 99.9);
    final gross = analyzer.simulate(sourceBars: source, visibleThrough: 40,
      side: PaperSide.buy, stopLoss: 95, takeProfit: 105, seed: 19);
    expect(gross.netMeanR, isNull);
    final explicitZero = analyzer.simulate(sourceBars: source,
      visibleThrough: 40, side: PaperSide.buy, stopLoss: 95,
      takeProfit: 105, seed: 19,
      costEstimate: const ReplayCostEstimate(roundTripPriceUnits: 0));
    expect(explicitZero.netMeanR, gross.meanR,
      reason: 'explicit zero-cost input is distinct from no estimate');
    const costs = ReplayCostEstimate(roundTripPriceUnits: 1);
    final net = analyzer.simulate(sourceBars: source, visibleThrough: 40,
      side: PaperSide.buy, stopLoss: 95, takeProfit: 105,
      seed: 19, costEstimate: costs);
    expect(net.targetFirst, gross.targetFirst);
    expect(net.stopFirst, gross.stopFirst);
    expect(net.neither, gross.neither);
    expect(net.meanR, gross.meanR);
    expect(net.netMeanR, closeTo(gross.meanR - .2, 0.0000001));
    expect(net.netFifthPercentileR,
      closeTo(gross.fifthPercentileR - .2, 0.0000001));
    expect(net.netNinetyFifthPercentileR,
      closeTo(gross.ninetyFifthPercentileR - .2, 0.0000001));
    expect(() => analyzer.simulate(sourceBars: source, visibleThrough: 40,
      side: PaperSide.buy, stopLoss: 95, takeProfit: 105,
      costEstimate: const ReplayCostEstimate(roundTripPriceUnits: -1)),
      throwsFormatException);
  });
}
