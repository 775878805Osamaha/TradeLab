import '../data/market_api.dart';
import '../paper/paper_ledger.dart';
import 'replay_cost_estimate.dart';

enum ReplayTradeStatus { pending, open, stopped, targeted }

class ReplayTradeOutcome {
  const ReplayTradeOutcome({required this.status, required this.signalThrough,
    required this.visibleThrough, this.entryPrice, this.exitPrice,
    this.rMultiple, this.netRMultiple, this.exitBarIndex,
    this.ambiguousBar = false});

  final ReplayTradeStatus status;
  final int signalThrough;
  final int visibleThrough;
  final double? entryPrice;
  final double? exitPrice;
  /// Gross R; while status is open this is unrealized mark-to-market R.
  final double? rMultiple;
  /// Estimated net R; absent unless the user explicitly supplied costs.
  final double? netRMultiple;
  final int? exitBarIndex;
  final bool ambiguousBar;
}

/// Evaluates one historical hypothetical trade, without any broker activity.
/// A signal after bar t fills at the OPEN of t+1, never at the signal close.
/// Only sourceBars[0..visibleThrough) may influence the outcome.
class ReplayTradeEvaluator {
  const ReplayTradeEvaluator();

  ReplayTradeOutcome evaluate({required List<MarketBar> sourceBars,
    required int signalThrough, required int visibleThrough,
    required PaperSide side, required double stopLoss,
    required double takeProfit, ReplayCostEstimate? costEstimate}) {
    costEstimate?.validate();
    if (signalThrough < 1 || visibleThrough < 0 ||
        signalThrough > sourceBars.length ||
        visibleThrough > sourceBars.length ||
        !stopLoss.isFinite || stopLoss <= 0 ||
        !takeProfit.isFinite || takeProfit <= 0) {
      throw const FormatException('خطة Replay أو مؤشر الشموع غير صالح.');
    }
    if (visibleThrough <= signalThrough) {
      return ReplayTradeOutcome(status: ReplayTradeStatus.pending,
        signalThrough: signalThrough, visibleThrough: visibleThrough);
    }

    final direction = side == PaperSide.buy ? 1.0 : -1.0;
    var entry = 0.0;
    var risk = 0.0;
    var lastClose = 0.0;
    var lastTimestamp = -1;
    // Check only bars actually needed to resolve the outcome. A closed trade
    // must not copy, inspect, or depend on any later candle, even if thousands
    // of other candles are revealed at the current Replay cursor.
    for (var index = signalThrough; index < visibleThrough; index++) {
      final bar = sourceBars[index];
      _validateEvaluatedBar(bar, lastTimestamp);
      lastTimestamp = bar.timestamp;
      final candle = bar.candle;
      if (index == signalThrough) {
        entry = candle.open;
        if ((side == PaperSide.buy &&
                !(stopLoss < entry && takeProfit > entry)) ||
            (side == PaperSide.sell &&
                !(stopLoss > entry && takeProfit < entry))) {
          throw const FormatException(
            'فجوة سعر الافتتاح جعلت الوقف أو الهدف غير صالح بالنسبة لسعر التنفيذ.');
        }
        risk = (entry - stopLoss).abs();
      }
      lastClose = candle.close;
      final stopAtOpen = side == PaperSide.buy
          ? candle.open <= stopLoss : candle.open >= stopLoss;
      final targetAtOpen = side == PaperSide.buy
          ? candle.open >= takeProfit : candle.open <= takeProfit;
      final stopInside = side == PaperSide.buy
          ? candle.low <= stopLoss : candle.high >= stopLoss;
      final targetInside = side == PaperSide.buy
          ? candle.high >= takeProfit : candle.low <= takeProfit;

      // An adverse opening gap is charged at the worse opening price. A
      // favorable gap only credits the limit target, never a better fill.
      if (stopAtOpen || targetAtOpen || stopInside || targetInside) {
        final stopped = stopAtOpen || (!targetAtOpen && stopInside);
        final exit = stopped
            ? (stopAtOpen ? candle.open : stopLoss) : takeProfit;
        final grossR = (exit - entry) * direction / risk;
        return ReplayTradeOutcome(
          status: stopped ? ReplayTradeStatus.stopped : ReplayTradeStatus.targeted,
          signalThrough: signalThrough, visibleThrough: visibleThrough,
          entryPrice: entry, exitPrice: exit,
          rMultiple: grossR,
          netRMultiple: costEstimate?.netR(
            grossR: grossR, riskPerUnit: risk),
          exitBarIndex: index,
          ambiguousBar: !stopAtOpen && !targetAtOpen &&
              stopInside && targetInside,
        );
      }
    }
    final grossR = (lastClose - entry) * direction / risk;
    return ReplayTradeOutcome(status: ReplayTradeStatus.open,
      signalThrough: signalThrough, visibleThrough: visibleThrough,
      entryPrice: entry, rMultiple: grossR,
      netRMultiple: costEstimate?.netR(
        grossR: grossR, riskPerUnit: risk));
  }

  /// Matches market OHLC validation for the evaluated interval, without
  /// traversing unreached future candles or allocating a large sublist.
  void _validateEvaluatedBar(MarketBar bar, int previousTimestamp) {
    final c = bar.candle;
    if (bar.timestamp <= previousTimestamp || !c.open.isFinite ||
        !c.high.isFinite || !c.low.isFinite || !c.close.isFinite ||
        c.low <= 0 || c.low > c.high || c.open < c.low ||
        c.close < c.low || c.open > c.high || c.close > c.high) {
      throw const FormatException('ترتيب الشموع أو قيم OHLC غير صحيحة.');
    }
  }
}
