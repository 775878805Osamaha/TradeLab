import '../paper/paper_ledger.dart';
import 'replay_cost_estimate.dart';
import 'replay_lab_bridge.dart';
import 'replay_trade_evaluator.dart';

/// A signal recorded at the last *revealed, completed* source candle.
/// The timestamp, rather than a list index, survives historical prepends.
class ReplayObservedSignal {
  const ReplayObservedSignal({
    required this.accountKey,
    required this.symbol,
    required this.timeframe,
    required this.signalTimestamp,
    required this.signalOpen,
    required this.signalHigh,
    required this.signalLow,
    required this.signalClose,
    required this.side,
    required this.stopLoss,
    required this.takeProfit,
    this.costEstimate,
  });

  final String accountKey;
  final String symbol;
  final String timeframe;
  final int signalTimestamp;
  final double signalOpen;
  final double signalHigh;
  final double signalLow;
  final double signalClose;
  final PaperSide side;
  final double stopLoss;
  final double takeProfit;
  final ReplayCostEstimate? costEstimate;

  factory ReplayObservedSignal.fromSnapshot({
    required ReplayLabSnapshot snapshot,
    required PaperSide side,
    required double stopLoss,
    required double takeProfit,
    ReplayCostEstimate? costEstimate,
  }) {
    costEstimate?.validate();
    if (snapshot.bars.isEmpty || !stopLoss.isFinite || !takeProfit.isFinite ||
        stopLoss <= 0 || takeProfit <= 0) {
      throw const FormatException('يلزم اختيار وقف وهدف صالحين وإشارة تاريخية ظاهرة.');
    }
    final bar = snapshot.bars.last;
    final close = bar.candle.close;
    if (bar.timestamp <= 0 || !close.isFinite || close <= 0) {
      throw const FormatException('بيانات شمعة الإشارة غير صالحة. أعد تحميل المصدر.');
    }
    if ((side == PaperSide.buy && !(stopLoss < close && takeProfit > close)) ||
        (side == PaperSide.sell && !(stopLoss > close && takeProfit < close))) {
      throw const FormatException('ضع الوقف والهدف على الجانبين الصحيحين من سعر إشارة Replay.');
    }
    return ReplayObservedSignal(
      accountKey: snapshot.accountKey,
      symbol: snapshot.symbol,
      timeframe: snapshot.timeframe,
      signalTimestamp: bar.timestamp,
      signalOpen: bar.candle.open,
      signalHigh: bar.candle.high,
      signalLow: bar.candle.low,
      signalClose: close,
      side: side,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      costEstimate: costEstimate,
    );
  }
}

class ReplayObservedResult {
  const ReplayObservedResult({this.outcome, this.reason});

  final ReplayTradeOutcome? outcome;
  final String? reason;
  bool get available => outcome != null;
}

/// Stateless resolver: no broker orders, local journal writes or future candles.
/// Recalculates as the cursor advances (or rewinds) using a frozen prefix.
class ReplayObservedTradeTracker {
  const ReplayObservedTradeTracker();

  ReplayObservedResult inspect({
    required ReplayObservedSignal signal,
    required ReplayLabSnapshot snapshot,
  }) {
    if (signal.accountKey != snapshot.accountKey ||
        signal.symbol != snapshot.symbol ||
        signal.timeframe != snapshot.timeframe) {
      return const ReplayObservedResult(
        reason: 'تغيّر الحساب أو الرمز أو الإطار. ابدأ إشارة تدريبية جديدة.');
    }
    // Provider bars are chronologically validated. Binary search keeps a
    // frozen 100k+-candle Replay lookup cheap across repeated UI rebuilds.
    var low = 0;
    var high = snapshot.bars.length;
    while (low < high) {
      final middle = low + ((high - low) ~/ 2);
      if (snapshot.bars[middle].timestamp < signal.signalTimestamp) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final index = low;
    if (index == snapshot.bars.length ||
        snapshot.bars[index].timestamp != signal.signalTimestamp) {
      return const ReplayObservedResult(
        reason: 'شمعة الإشارة ليست ضمن الشموع الظاهرة. عد إليها داخل Replay.');
    }
    final anchor = snapshot.bars[index].candle;
    if (anchor.open != signal.signalOpen ||
        anchor.high != signal.signalHigh ||
        anchor.low != signal.signalLow ||
        anchor.close != signal.signalClose) {
      return const ReplayObservedResult(
        reason: 'تغيّرت بيانات OHLC لشمعة الإشارة من المصدر؛ لا يمكن متابعة النتيجة السابقة.');
    }
    try {
      return ReplayObservedResult(outcome: const ReplayTradeEvaluator().evaluate(
        sourceBars: snapshot.bars,
        signalThrough: index + 1,
        visibleThrough: snapshot.bars.length,
        side: signal.side,
        stopLoss: signal.stopLoss,
        takeProfit: signal.takeProfit,
        costEstimate: signal.costEstimate,
      ));
    } on FormatException catch (error) {
      // A large next-bar opening gap can invalidate the original plan;
      // never force a fictional fill through the stop or target.
      return ReplayObservedResult(reason: error.message.toString());
    }
  }
}
