import 'dart:math' as math;

import '../data/market_api.dart';
import '../paper/paper_ledger.dart';
import 'replay_cost_estimate.dart';

class ReplayScenarioResult {
  const ReplayScenarioResult({required this.samples, required this.seed,
    required this.visibleBars, required this.horizonBars,
    required this.entryPrice, required this.targetFirst,
    required this.stopFirst, required this.neither,
    required this.meanR, required this.fifthPercentileR,
    required this.ninetyFifthPercentileR,
    this.netMeanR, this.netFifthPercentileR,
    this.netNinetyFifthPercentileR});

  final int samples;
  final int seed;
  final int visibleBars;
  final int horizonBars;
  final double entryPrice;
  final int targetFirst;
  final int stopFirst;
  final int neither;
  final double meanR;
  final double fifthPercentileR;
  final double ninetyFifthPercentileR;
  /// Null means costs were NOT provided, not that execution was free.
  final double? netMeanR;
  final double? netFifthPercentileR;
  final double? netNinetyFifthPercentileR;

  double get targetProbability => 100 * targetFirst / samples;
  double get stopProbability => 100 * stopFirst / samples;
  double get neitherProbability => 100 * neither / samples;
}

/// A read-only, seeded bootstrap from *visible, completed* source OHLC bars.
/// This is a scenario distribution, not a backtest or a forecast.
class ReplayScenarioAnalyzer {
  const ReplayScenarioAnalyzer();

  ReplayScenarioResult simulate({required List<MarketBar> sourceBars,
      required int visibleThrough,
      required PaperSide side, required double stopLoss,
      required double takeProfit, int horizonBars = 20,
      int samples = 1000, int seed = 19,
      ReplayCostEstimate? costEstimate}) {
    costEstimate?.validate();
    if (visibleThrough < 1 || visibleThrough > sourceBars.length) {
      throw const FormatException('مؤشر Replay خارج نطاق الشموع المتاحة.');
    }
    // Deliberately copy the prefix before inspecting OHLC or building a pool.
    // Even a caller holding future candles cannot leak them into the result.
    final visibleBars = List<MarketBar>.unmodifiable(
        sourceBars.take(visibleThrough));
    if (visibleBars.length < 30 || horizonBars < 1 || horizonBars > 500 ||
        samples < 1 || samples > 10000) {
      throw const FormatException('تحتاج المحاكاة إلى 30 شمعة مغلقة على الأقل وإعدادات صالحة.');
    }
    validateBars(visibleBars);
    final entry = visibleBars.last.candle.close;
    if (!stopLoss.isFinite || !takeProfit.isFinite || stopLoss <= 0 ||
        takeProfit <= 0 ||
        (side == PaperSide.buy && !(stopLoss < entry && takeProfit > entry)) ||
        (side == PaperSide.sell && !(stopLoss > entry && takeProfit < entry))) {
      throw const FormatException('وقف الخسارة والهدف غير متوافقين مع اتجاه الصفقة.');
    }
    final risk = (entry - stopLoss).abs();
    final direction = side == PaperSide.buy ? 1.0 : -1.0;
    final pool = <(double, double, double, double)>[];
    for (var i = 1; i < visibleBars.length; i++) {
      final previous = visibleBars[i - 1].candle.close;
      final bar = visibleBars[i].candle;
      pool.add((bar.open / previous, bar.high / previous,
          bar.low / previous, bar.close / previous));
    }
    final rng = math.Random(seed);
    final outcomes = <double>[];
    var stopped = 0, targeted = 0, unfilled = 0;
    for (var sample = 0; sample < samples; sample++) {
      var price = entry;
      var outcome = 0; // -1 stop, 1 target, 0 neither
      for (var step = 0; step < horizonBars; step++) {
        final ratios = pool[rng.nextInt(pool.length)];
        final open = price * ratios.$1;
        final high = price * ratios.$2;
        final low = price * ratios.$3;
        final close = price * ratios.$4;
        if (side == PaperSide.buy) {
          // Opening gaps execute at the opening price. If both levels touch
          // inside one bar, pessimistically count the stop first.
          if (open <= stopLoss) { price = open; outcome = -1; break; }
          if (open >= takeProfit) { price = takeProfit; outcome = 1; break; }
          if (low <= stopLoss) { price = stopLoss; outcome = -1; break; }
          if (high >= takeProfit) { price = takeProfit; outcome = 1; break; }
        } else {
          if (open >= stopLoss) { price = open; outcome = -1; break; }
          if (open <= takeProfit) { price = takeProfit; outcome = 1; break; }
          if (high >= stopLoss) { price = stopLoss; outcome = -1; break; }
          if (low <= takeProfit) { price = takeProfit; outcome = 1; break; }
        }
        price = close;
      }
      if (outcome < 0) stopped++;
      else if (outcome > 0) targeted++;
      else unfilled++;
      // Gross R: spread, fees and slippage are not available in OHLC data.
      outcomes.add((price - entry) * direction / risk);
    }
    outcomes.sort();
    final mean = outcomes.reduce((a, b) => a + b) / samples;
    final fifth = outcomes[((samples - 1) * .05).floor()];
    final ninetyFifth = outcomes[((samples - 1) * .95).floor()];
    return ReplayScenarioResult(samples: samples, seed: seed,
      visibleBars: visibleBars.length, horizonBars: horizonBars,
      entryPrice: entry, targetFirst: targeted, stopFirst: stopped,
      neither: unfilled, meanR: mean,
      fifthPercentileR: fifth, ninetyFifthPercentileR: ninetyFifth,
      netMeanR: costEstimate?.netR(grossR: mean, riskPerUnit: risk),
      netFifthPercentileR: costEstimate?.netR(
        grossR: fifth, riskPerUnit: risk),
      netNinetyFifthPercentileR: costEstimate?.netR(
        grossR: ninetyFifth, riskPerUnit: risk));
  }
}
